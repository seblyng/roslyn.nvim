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
            vim.notify("Roslyn project initialization complete", vim.log.levels.INFO, { title = "roslyn.nvim" })

            local buffers = vim.lsp.get_buffers_by_client_id(ctx.client_id)
            for _, buf in ipairs(buffers) do
                vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
            end

            vim.api.nvim_exec_autocmds("User", { pattern = "RoslynInitialized", modeline = false })
        end,
        ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
            vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR, {
                title = "roslyn.nvim",
            })
            return vim.NIL
        end,
        ["workspace/_roslyn_projectNeedsRestore"] = function(_, result, ctx)
            local client = vim.lsp.get_client_by_id(ctx.client_id)
            assert(client)

            client.request("workspace/_roslyn_restore", result, function(err, response)
                if err then
                    vim.notify(err.message, vim.log.levels.ERROR, { title = "roslyn.nvim" })
                end
                if response then
                    for _, v in ipairs(response) do
                        vim.notify(v.message, vim.log.levels.INFO, { title = "roslyn.nvim" })
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
            vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
        end)
        if roslyn_config.config.on_exit then
            roslyn_config.config.on_exit(code, signal, client_id)
        end
    end

    server.start_server(bufnr, cmd, config)
end

---@param exe string|string[]
---@param args string[]
---@return string[]
local function get_cmd(exe, args)
    local mason_installation = get_mason_installation()
    local mason_exists = vim.uv.fs_stat(mason_installation) ~= nil

    if type(exe) == "string" then
        return vim.list_extend({ exe }, args)
    elseif type(exe) == "table" then
        return vim.list_extend(vim.deepcopy(exe), args)
    elseif mason_exists then
        return vim.list_extend({ mason_installation }, args)
    else
        return vim.list_extend({
            "dotnet",
            vim.fs.joinpath(
                vim.fn.stdpath("data") --[[@as string]],
                "roslyn",
                "Microsoft.CodeAnalysis.LanguageServer.dll"
            ),
        }, args)
    end
end

---@class InternalRoslynNvimConfig
---@field filewatching boolean
---@field exe? string|string[]
---@field args string[]
---@field config vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field broad_search boolean
---@field allow_csproj_for_sln_swap boolean

---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field args? string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field broad_search? boolean
---@field allow_csproj_for_sln_swap? boolean

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
    commands.attach_subcommand_to_buffer("target", bufnr, {
        impl = function()
            vim.ui.select(sln, { prompt = "Select target solution: " }, function(file)
                vim.lsp.stop_client(vim.lsp.get_clients({ name = "roslyn" }), true)
                vim.g.roslyn_nvim_selected_solution = file
                lsp_start(cmd, bufnr, vim.fs.dirname(file), roslyn_config, on_init(file))
            end)
        end,
    })

    local sln_file = get_sln_file(bufnr, sln, roslyn_config)
    if sln_file then
        vim.g.roslyn_nvim_selected_solution = sln_file
        return lsp_start(cmd, bufnr, vim.fs.dirname(sln_file), roslyn_config, on_init(sln_file))
    end

    -- If we are here, then we
    --   - Don't have a selected solution file
    --   - Found multiple solution files
    --   - Was not able to predict which solution file to use
    vim.notify(
        "Multiple sln files found. Use `:Roslyn target` to select or change target for buffer",
        vim.log.levels.INFO,
        { title = "roslyn.nvim" }
    )
end

---@param cmd string[]
---@param bufnr integer
---@param csproj RoslynNvimDirectoryWithFiles
---@param roslyn_config InternalRoslynNvimConfig
local function start_with_projects(cmd, bufnr, csproj, roslyn_config)
    lsp_start(cmd, bufnr, csproj.directory, roslyn_config, function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
        client.notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, csproj.files),
        })
    end)
end

local function try_setup_mason()
    local ok, mason = pcall(require, "mason")
    if not ok then
        return
    end

    local registry = "github:Crashdummyy/mason-registry"
    local settings = require("mason.settings")

    local registries = vim.deepcopy(settings.current.registries)
    if not vim.list_contains(registries, registry) then
        table.insert(registries, registry)
    end

    if mason.has_setup then
        require("mason-registry.sources").set_registries(registries)
    else
        -- HACK: Insert the registry into the default registries
        -- If the user calls setup and specifies the `registries` themselves
        -- this will not work. However, if they do that, they should also
        -- just provide the registry themselves
        table.insert(settings._DEFAULT_SETTINGS.registries, registry)
    end
end

---@param config? RoslynNvimConfig
function M.setup(config)
    try_setup_mason()

    vim.treesitter.language.register("c_sharp", "csharp")

    ---@type InternalRoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = nil,
        args = { "--logLevel=Information", "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()) },
        ---@diagnostic disable-next-line: missing-fields
        config = {},
        choose_sln = nil,
        broad_search = false,
        allow_csproj_for_sln_swap = true,
    }

    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})
    roslyn_config.config.capabilities = get_extendend_capabilities(roslyn_config)

    local cmd = get_cmd(roslyn_config.exe, roslyn_config.args)

    ---@param target string
    local function on_init_sln(target)
        return function(client)
            vim.notify("Initializing Roslyn client for " .. target, vim.log.levels.INFO, { title = "roslyn.nvim" })
            client.notify("solution/open", {
                solution = vim.uri_from_fname(target),
            })
        end
    end

    vim.api.nvim_create_autocmd({ "FileType" }, {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = "cs",
        callback = function(opt)
            if not valid_buffer(opt.buf) then
                return
            end

            commands.create_roslyn_commands()
            local allow_projects = not vim.g.roslyn_nvim_selected_solution
                or roslyn_config.allow_csproj_for_sln_swap ~= false

            local csproj_files = allow_projects and utils.try_get_csproj_files()
            if csproj_files then
                return start_with_projects(cmd, opt.buf, csproj_files, roslyn_config)
            end

            local sln_files = utils.get_solution_files(opt.buf, roslyn_config.broad_search)
            if sln_files and not vim.tbl_isempty(sln_files) then
                return start_with_solution(opt.buf, cmd, sln_files, roslyn_config, on_init_sln)
            end

            local csproj = allow_projects and utils.get_project_files(opt.buf)
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
