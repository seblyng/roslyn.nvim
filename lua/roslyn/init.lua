local server = require("roslyn.server")
local utils = require("roslyn.slnutils")

---@param buf number
---@return boolean
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

---@return string
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

---@param pipe string
---@param root_dir string
---@param roslyn_config InternalRoslynNvimConfig
---@param on_init fun(client: vim.lsp.Client)
local function lsp_start(pipe, root_dir, roslyn_config, on_init)
    local config = vim.deepcopy(roslyn_config.config)
    config.name = "roslyn"
    config.cmd = vim.lsp.rpc.connect(pipe)
    config.root_dir = root_dir
    config.handlers = vim.tbl_deep_extend("force", {
        ["client/registerCapability"] = require("roslyn.hacks").with_filtered_watchers(
            vim.lsp.handlers["client/registerCapability"],
            roslyn_config.filewatching
        ),
        ["workspace/projectInitializationComplete"] = function(_, _, ctx)
            vim.notify("Roslyn project initialization complete", vim.log.levels.INFO)

            local buffers = vim.lsp.get_buffers_by_client_id(ctx.client_id)
            for _, buf in ipairs(buffers) do
                vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
            end
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
    config.on_init = function(client, initialize_result)
        if roslyn_config.config.on_init then
            roslyn_config.config.on_init(client, initialize_result)
        end
        on_init(client)

        local commands = require("roslyn.commands")
        commands.fix_all_code_action(client)
        commands.nested_code_action(client)
    end

    config.on_exit = function(code, signal, client_id)
        vim.g.roslyn_nvim_selected_solution = nil
        server.stop_server()
        vim.schedule(function()
            vim.notify("Roslyn server stopped", vim.log.levels.INFO)
        end)
        if roslyn_config.config.on_exit then
            roslyn_config.config.on_exit(code, signal, client_id)
        end
    end

    vim.lsp.start(config, {
        reuse_client = function(client, _config)
            if vim.g.roslyn_nvim_selected_solution and client.name == _config.name then
                return true
            end

            return false
        end,
    })
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
---@field choose_sln? fun(solutions: string[]): string?
---
---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?

local M = {}

---Runs roslyn server (if not running already) and then lsp_start
---@param cmd string[]
---@param root_dir string
---@param roslyn_config InternalRoslynNvimConfig
---@param on_init fun(client: vim.lsp.Client)
local function wrap_roslyn(cmd, root_dir, roslyn_config, on_init)
    server.start_server(cmd, function(pipe_name)
        lsp_start(pipe_name, root_dir, roslyn_config, on_init)
    end)
end

-- If we only have one solution file, then use that.
-- If the user have provided a hook to select a solution file, use that
-- If not, we must have multiple, and we try to predict the correct solution file
---@param bufnr number
---@param sln string[]
---@param roslyn_config InternalRoslynNvimConfig
local function get_sln_file(bufnr, sln, roslyn_config)
    if #sln == 1 then
        return sln[1]
    end

    local chosen = roslyn_config.choose_sln and roslyn_config.choose_sln(sln)
    if chosen then
        return chosen
    end

    return utils.predict_sln_file(bufnr, sln)
end

---@param bufnr number
---@param cmd string[]
---@param sln string[]
---@param roslyn_config InternalRoslynNvimConfig
---@param on_init fun(target: string): fun(client: vim.lsp.Client)
local function start_with_solution(bufnr, cmd, sln, roslyn_config, on_init)
    -- Give the user an option to change the solution file if we find more than one
    -- Or the selected solution file is not a part of the solution files found.
    -- If the solution file is not a part of the found solution files, it may be
    -- that the user has completely changed projects, and we can then support changing the
    -- solution file without completely restarting neovim
    if
        #sln > 1
        or (vim.g.roslyn_nvim_selected_solution and not vim.iter(sln or {}):find(vim.g.roslyn_nvim_selected_solution))
    then
        vim.api.nvim_buf_create_user_command(bufnr, "CSTarget", function()
            vim.ui.select(sln, { prompt = "Select target solution: " }, function(file)
                vim.lsp.stop_client(vim.lsp.get_clients({ name = "roslyn" }), true)
                vim.g.roslyn_nvim_selected_solution = file
                local dir = vim.fs.root(0, file) --[[@as string]]
                wrap_roslyn(cmd, dir, roslyn_config, on_init(file))
            end)
        end, { desc = "Selects the sln file for the buffer: " .. bufnr })
    end

    local sln_file = get_sln_file(bufnr, sln, roslyn_config)
    if sln_file then
        vim.g.roslyn_nvim_selected_solution = sln_file
        local sln_dir = vim.fs.root(bufnr, sln_file) --[[@as string]]
        return wrap_roslyn(cmd, sln_dir, roslyn_config, on_init(sln_file))
    end

    -- If we are here, then we
    --   - Don't have a selected solution file
    --   - Found multiple solution files
    --   - Was not able to predict which solution file to use
    vim.notify("Multiple sln files found. Use `CSTarget` to select or change target for buffer", vim.log.levels.INFO)
end

---@param cmd string[]
---@param csproj RoslynNvimDirectoryWithFiles
---@param roslyn_config InternalRoslynNvimConfig
local function start_with_projects(cmd, csproj, roslyn_config)
    wrap_roslyn(cmd, csproj.directory, roslyn_config, function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO)
        client.notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, csproj.files),
        })
    end)
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
        choose_sln = nil,
    }

    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})
    roslyn_config.config.capabilities = get_extendend_capabilities(roslyn_config)

    local cmd = get_cmd(roslyn_config.exe)

    ---@param target string
    local function on_init_sln(target)
        return function(client)
            vim.notify("Initializing Roslyn client for " .. target, vim.log.levels.INFO)
            client.notify("solution/open", {
                solution = vim.uri_from_fname(target),
            })
        end
    end

    vim.api.nvim_create_autocmd({ "BufEnter" }, {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = "*.cs",
        callback = function(opt)
            if not valid_buffer(opt.buf) then
                return
            end

            local csproj_files = utils.try_get_csproj_files(opt.buf)
            if csproj_files then
                return start_with_projects(cmd, csproj_files, roslyn_config)
            end

            local sln_files = utils.get_solution_files(opt.buf)
            if sln_files and not vim.tbl_isempty(sln_files) then
                return start_with_solution(opt.buf, cmd, sln_files, roslyn_config, on_init_sln)
            end

            local csproj = utils.get_project_files(opt.buf)
            if csproj then
                return start_with_projects(cmd, csproj, roslyn_config)
            end

            -- Fallback to the selected solution if we don't find anything.
            -- This makes it work kind of like vscode for the decoded files
            if vim.g.roslyn_nvim_selected_solution then
                local sln_dir = vim.fs.root(opt.buf, vim.g.roslyn_nvim_selected_solution) --[[@as string]]
                return wrap_roslyn(cmd, sln_dir, roslyn_config, on_init_sln(vim.g.roslyn_nvim_selected_solution))
            end
        end,
    })
end

return M
