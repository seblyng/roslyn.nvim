local roslyn_emitter = require("roslyn.roslyn_emitter")
local server = require("roslyn.server")
local utils = require("roslyn.slnutils")
local commands = require("roslyn.commands")

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

---@param cmd string[]
---@param bufnr integer
---@param root_dir string
---@param roslyn_config InternalRoslynNvimConfig
---@param on_init fun(client: vim.lsp.Client)
local function lsp_start(cmd, bufnr, root_dir, roslyn_config, on_init)
    local config = vim.deepcopy(roslyn_config.config)
    config.name = "roslyn"
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

        local lsp_commands = require("roslyn.lsp_commands")
        lsp_commands.fix_all_code_action(client)
        lsp_commands.nested_code_action(client)
    end

    config.on_exit = function(code, signal, client_id)
        vim.g.roslyn_nvim_selected_solution = nil
        server.stop_server(client_id)
        vim.schedule(function()
            vim.notify("Roslyn server stopped", vim.log.levels.INFO)
            roslyn_emitter:emit_stopped()
        end)
        if roslyn_config.config.on_exit then
            roslyn_config.config.on_exit(code, signal, client_id)
        end
    end

    server.start_server(cmd, config, function(pipe_name)
        config.cmd = vim.lsp.rpc.connect(pipe_name)
        local client_id = vim.lsp.start(config, {
            bufnr = bufnr,
        })
        if client_id then
            server.save_server_object(client_id)
        end
    end)
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
---@field broad_search boolean

---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field broad_search? boolean

local M = {}

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
        local function select_target_solution()
            vim.ui.select(sln, { prompt = "Select target solution: " }, function(file)
                vim.lsp.stop_client(vim.lsp.get_clients({ name = "roslyn" }), true)
                vim.g.roslyn_nvim_selected_solution = file
                lsp_start(cmd, bufnr, vim.fs.dirname(file), roslyn_config, on_init(file))
            end)
        end

        commands.attach_subcommand_to_buffer("target", bufnr, {
            impl = function()
                select_target_solution()
            end,
        })

        vim.api.nvim_buf_create_user_command(bufnr, "CSTarget", function()
            vim.notify("Deprecated... Use `:Roslyn target` instead", vim.log.levels.WARN)
            select_target_solution()
        end, { desc = "Selects the sln file for the buffer: " .. bufnr })
    end

    local sln_file = get_sln_file(bufnr, sln, roslyn_config)
    if sln_file then
        vim.g.roslyn_nvim_selected_solution = sln_file
        return lsp_start(cmd, bufnr, vim.fs.dirname(sln_file), roslyn_config, on_init(sln_file))
    end

    -- If we are here, then we
    --   - Don't have a selected solution file
    --   - Found multiple solution files
    --   - Was not able to predict which solution file to use
    vim.notify("Multiple sln files found. Use `CSTarget` to select or change target for buffer", vim.log.levels.INFO)
end

---@param cmd string[]
---@param bufnr integer
---@param csproj RoslynNvimDirectoryWithFiles
---@param roslyn_config InternalRoslynNvimConfig
local function start_with_projects(cmd, bufnr, csproj, roslyn_config)
    lsp_start(cmd, bufnr, csproj.directory, roslyn_config, function(client)
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
    commands.create_roslyn_commands()

    ---@type InternalRoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = nil,
        ---@diagnostic disable-next-line: missing-fields
        config = {},
        choose_sln = nil,
        broad_search = false,
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

            local csproj_files = utils.try_get_csproj_files()
            if csproj_files then
                return start_with_projects(cmd, opt.buf, csproj_files, roslyn_config)
            end

            local sln_files = utils.get_solution_files(opt.buf, roslyn_config.broad_search)
            if sln_files and not vim.tbl_isempty(sln_files) then
                return start_with_solution(opt.buf, cmd, sln_files, roslyn_config, on_init_sln)
            end

            local csproj = utils.get_project_files(opt.buf)
            if csproj then
                return start_with_projects(cmd, opt.buf, csproj, roslyn_config)
            end

            -- Fallback to the selected solution if we don't find anything.
            -- This makes it work kind of like vscode for the decoded files
            if vim.g.roslyn_nvim_selected_solution then
                local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
                return lsp_start(cmd, opt.buf, sln_dir, roslyn_config, on_init_sln(vim.g.roslyn_nvim_selected_solution))
            end
        end,
    })
end

return M
