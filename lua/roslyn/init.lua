local server = require("roslyn.server")
local utils = require("roslyn.slnutils")

---@param buf number
local function valid_buffer(buf)
    local bufname = vim.api.nvim_buf_get_name(buf)
    return vim.bo[buf].buftype ~= "nofile"
        and (
            bufname:match("^/")
            or bufname:match("^[a-zA-Z]:")
            or bufname:match("^zipfile://")
            or bufname:match("^tarfile:")
        )
end

local function get_mason_installation()
    local mason_installation = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "mason", "bin", "roslyn")
    return vim.uv.os_uname().sysname == "Windows_NT" and string.format("%s.cmd", mason_installation)
        or mason_installation
end

---Assigns the default capabilities from cmp if installed, and the capabilities from neovim
---@return lsp.ClientCapabilities
local function get_default_capabilities()
    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    return ok
            and vim.tbl_deep_extend(
                "force",
                vim.lsp.protocol.make_client_capabilities(),
                cmp_nvim_lsp.default_capabilities()
            )
        or vim.lsp.protocol.make_client_capabilities()
end

---Extends the default capabilities with hacks
---@param roslyn_config InternalRoslynNvimConfig
---@return lsp.ClientCapabilities
local function get_extendend_capabilities(roslyn_config)
    local capabilities = roslyn_config.config.capabilities or get_default_capabilities()
    -- This actually tells the server that the client can do filewatching.
    -- We will then later just not watch any files. This is because the server
    -- will fallback to its own filewatching which is super slow.

    -- Default value is true, so the user needs to explicitly pass `false` for this to happen
    -- `not filewatching` evaluates to true if the user don't provide a value for this
    if roslyn_config and roslyn_config.filewatching == false then
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
---@param root_with_files RoslynNvimDirectoryWithFiles
---@param config vim.lsp.ClientConfig
---@param filewatching boolean
local function lsp_start(pipe, root_with_files, config, filewatching)
    config.name = "roslyn"
    config.cmd = vim.lsp.rpc.connect(pipe)
    config.root_dir = root_with_files.directory
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
        local target = known_solutions[root_with_files.directory]
        if target and target:match("%.sln$") then
            vim.notify("Initializing Roslyn client for " .. target, vim.log.levels.INFO)
            client.notify("solution/open", {
                solution = vim.uri_from_fname(target),
            })
        else
            vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO)
            local projects = vim.iter(root_with_files.files)
                :map(function(file)
                    return vim.uri_from_fname(file)
                end)
                :totable()
            client.notify("project/open", {
                projects = projects,
            })
        end

        local commands = require("roslyn.commands")
        commands.fix_all_code_action(client)
        commands.nested_code_action(client)
    end

    config.on_exit = function(_, _, _)
        known_solutions[root_with_files.directory] = nil
        if vim.tbl_count(known_solutions) == 0 then
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

---@class InternalRoslynNvimConfig
---@field filewatching boolean
---@field exe? string|string[]
---@field config vim.lsp.ClientConfig
---
---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field config? vim.lsp.ClientConfig

local M = {}

---Runs roslyn server (if not running already) and then lsp_start
---@param cmd string[]
---@param root_with_files RoslynNvimDirectoryWithFiles
---@param roslyn_config InternalRoslynNvimConfig
local function wrap_roslyn(cmd, root_with_files, roslyn_config)
    server.start_server(cmd, function(pipe_name)
        lsp_start(pipe_name, root_with_files, roslyn_config.config, roslyn_config.filewatching)
    end)
end

---@param bufnr number
---@param cmd string[]
---@param sln RoslynNvimDirectoryWithFiles
---@param roslyn_config InternalRoslynNvimConfig
local function start_with_solution(bufnr, cmd, sln, roslyn_config)
    -- Roslyn is already running, so just call `vim.lsp.start` to handle everything
    if known_solutions[sln.directory] then
        return wrap_roslyn(cmd, sln, roslyn_config)
    end

    -- Only one solution file is found. Start roslyn with that as root dir
    if #sln.files == 1 then
        known_solutions[sln.directory] = sln.files[1]
        return wrap_roslyn(cmd, sln, roslyn_config)
    end

    -- Multiple sln files found, let's try to predict which one is the correct one for the current buffer
    local predicted_sln_file = utils.predict_sln_file(bufnr, sln)
    if predicted_sln_file then
        known_solutions[sln.directory] = predicted_sln_file
        wrap_roslyn(cmd, sln, roslyn_config)
    end

    vim.notify_once("Multiple sln files found. You can use `CSTarget` to select target for buffer", vim.log.levels.INFO)

    vim.api.nvim_buf_create_user_command(bufnr, "CSTarget", function()
        vim.ui.select(sln.files, { prompt = "Select target solution: " }, function(sln_file)
            known_solutions[sln.directory] = sln_file
            wrap_roslyn(cmd, sln, roslyn_config)
        end)
    end, { desc = "Selects the sln file for the buffer: " .. bufnr })
end

---@param config? RoslynNvimConfig
function M.setup(config)
    vim.treesitter.language.register("c_sharp", "csharp")

    ---@type InternalRoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = nil,
        ---@diagnostic disable-next-line: missing-fields
        config = {},
    }

    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})
    roslyn_config.config.capabilities = get_extendend_capabilities(roslyn_config)

    local cmd = get_cmd(roslyn_config.exe)

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = { "cs" },
        callback = function(opt)
            if not valid_buffer(opt.buf) then
                return
            end

            local sln = utils.get_directory_with_files(opt.buf, "sln")
            if sln then
                return start_with_solution(opt.buf, cmd, sln, roslyn_config)
            end

            local csproj = utils.get_directory_with_files(opt.buf, "csproj")
            if csproj then
                return wrap_roslyn(cmd, csproj, roslyn_config)
            end
        end,
    })
end

return M
