local server = require("roslyn.server")

---@param bufname string
local function bufname_valid(bufname)
    return bufname:match("^/")
        or bufname:match("^[a-zA-Z]:")
        or bufname:match("^zipfile://")
        or bufname:match("^tarfile:")
end

local function get_mason_installation()
    local mason_installation = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "mason", "bin", "roslyn")
    return vim.uv.os_uname().sysname == "Windows_NT" and string.format("%s.cmd", mason_installation)
        or mason_installation
end

-- Assigns the default capabilities from cmp if installed, and the capabilities from neovim
-- Merges it in with any user configured capabilities if provided
---@param filewatching boolean
local function get_default_capabilities(filewatching)
    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    local capabilities = ok
            and vim.tbl_deep_extend(
                "force",
                vim.lsp.protocol.make_client_capabilities(),
                cmp_nvim_lsp.default_capabilities()
            )
        or vim.lsp.protocol.make_client_capabilities()

    -- This actually tells the server that the client can do filewatching.
    -- We will then later just not watch any files. This is because the server
    -- will fallback to its own filewatching which is super slow.
    -- Default value is true, so the user needs to explicitly pass `false` for this to happen
    -- `not filewatching` evaluates to true if the user don't provide a value for this
    if not filewatching then
        capabilities = vim.tbl_deep_extend("force", capabilities, {
            workspace = {
                didChangeWatchedFiles = {
                    dynamicRegistration = true,
                },
            },
        })
    end

    -- HACK: Roslyn requires the dynamicRegistration to be set to support diagnostics for some reason
    return vim.tbl_deep_extend("force", capabilities, {
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    })
end

---@type table<string, string>
---Key is solution directory, and value is sln target
local known_solutions = {}

---@param pipe string
---@param target string
---@param config? vim.lsp.ClientConfig
---@param filewatching boolean
local function lsp_start(pipe, target, config, filewatching)
    local sln_directory = vim.fs.dirname(target)
    config = config or {}
    config.name = "roslyn"
    config.cmd = vim.lsp.rpc.connect(pipe)
    config.root_dir = sln_directory
    config.capabilities = get_default_capabilities(filewatching)
    config.handlers = vim.tbl_deep_extend("force", {
        ["client/registerCapability"] = require("roslyn.hacks").with_filtered_watchers(
            vim.lsp.handlers["client/registerCapability"],
            filewatching
        ),
        ["workspace/projectInitializationComplete"] = function()
            vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)
        end,
        ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
            vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR)
            return vim.NIL
        end,
        ["workspace/_roslyn_projectNeedsRestore"] = function(_, result, ctx)
            local client = vim.lsp.get_client_by_id(ctx.client_id)
            assert(client)

            client.request("workspace/_roslyn_restore", result, function(err, response)
                if err then
                    vim.notify(err.message, vim.log.levels.ERROR)
                end
                if response then
                    for _, v in ipairs(response) do
                        vim.notify(v.message)
                    end
                end
            end)

            return vim.NIL
        end,
    }, config.handlers or {})
    config.on_init = function(client)
        vim.notify("Initializing Roslyn client for " .. target, vim.log.levels.INFO)
        client.notify("solution/open", {
            ["solution"] = vim.uri_from_fname(target),
        })

        local commands = require("roslyn.commands")
        commands.fix_all_code_action(client)
        commands.nested_code_action(client)
    end

    config.on_exit = function(_, _, _)
        known_solutions[sln_directory] = nil
        if #known_solutions == 0 then
            server.stop_server()
        end
    end

    vim.lsp.start(config)
end

---@param exe string|string[]
---@return string[]
local function get_cmd(exe)
    local default_lsp_args =
        { "--logLevel=Information", "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()) }
    local mason_installation = get_mason_installation()

    if type(exe) == "string" then
        return vim.list_extend({ exe }, default_lsp_args)
    elseif type(exe) == "table" then
        return vim.list_extend(vim.deepcopy(exe), default_lsp_args)
    elseif vim.uv.fs_stat(mason_installation) then
        return vim.list_extend({ mason_installation }, default_lsp_args)
    else
        return vim.list_extend({
            "dotnet",
            vim.fs.joinpath(
                vim.fn.stdpath("data") --[[@as string]],
                "roslyn",
                "Microsoft.CodeAnalysis.LanguageServer.dll"
            ),
        }, default_lsp_args)
    end
end

---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field config? vim.lsp.ClientConfig

local M = {}

---Runs roslyn server (if not running already) and then lsp_start
---@param sln_file string
---@param roslyn_config RoslynNvimConfig
local function wrap_roslyn(sln_file, roslyn_config)
    local cmd = get_cmd(roslyn_config.exe)
    server.start_server(cmd, function(pipe_name)
        lsp_start(pipe_name, sln_file, roslyn_config.config, roslyn_config.filewatching)
    end)
end

---@param config? RoslynNvimConfig
function M.setup(config)
    vim.treesitter.language.register("c_sharp", "csharp")

    ---@type RoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = nil,
    }

    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = { "cs" },
        callback = function(opt)
            local bufname = vim.api.nvim_buf_get_name(opt.buf)

            if vim.bo["buftype"] == "nofile" or not bufname_valid(bufname) then
                return
            end

            local sln_directory = require("roslyn.slnutils").get_sln_directory(opt.buf)

            if not sln_directory then
                return
            end

            -- Roslyn is already running, so just call `vim.lsp.start` to handle everything
            if known_solutions[sln_directory] then
                wrap_roslyn(known_solutions[sln_directory], roslyn_config)
                return
            end

            local all_sln_files = require("roslyn.slnutils").get_all_sln_files(opt.buf)

            if not all_sln_files then
                return
            end

            vim.api.nvim_create_user_command("CSTarget", function()
                vim.ui.select(all_sln_files, { prompt = "Select target solution: " }, function(sln_file)
                    known_solutions[sln_directory] = sln_file
                    wrap_roslyn(sln_file, roslyn_config)
                end)
            end, { desc = "Selects the sln file for the current buffer" })

            if #all_sln_files == 1 then
                wrap_roslyn(all_sln_files[1], roslyn_config)
                known_solutions[sln_directory] = all_sln_files[1]

                return
            end

            -- Multiple sln files found, let's try to predict which one is the correct one for the current buffer
            local predicted_sln_file = require("roslyn.slnutils").predict_sln_file(opt.buf)

            if predicted_sln_file then
                wrap_roslyn(predicted_sln_file, roslyn_config)
                known_solutions[sln_directory] = predicted_sln_file
            end

            vim.notify_once(
                "Multiple sln files found. You can use `CSTarget` to select target for buffer",
                vim.log.levels.INFO
            )
        end,
    })
end

return M
