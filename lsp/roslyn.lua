local function get_default_cmd()
    local resolved = require("roslyn.utils").get_roslyn_lsp_path()
    local exe = resolved or "Microsoft.CodeAnalysis.LanguageServer"

    local cmd = { exe, "--stdio" }

    local roslyn_extensions = require("roslyn.config").get().extensions or {}
    if next(roslyn_extensions) then
        vim.deprecate("roslyn.nvim extensions", 'vim.lsp.config("roslyn", { cmd = ... })', "soon", "roslyn.nvim")
    end

    for ext_name, extension in pairs(roslyn_extensions) do
        if extension.enabled then
            local resolved_config = type(extension.config) == "function" and extension.config() or extension.config

            local resolved_path = type(resolved_config.path) == "function" and resolved_config.path()
                or resolved_config.path

            if resolved_path == nil then
                vim.notify(
                    string.format("Extension '%s' is enabled but no path was provided. Skipping...", ext_name),
                    vim.log.levels.WARN,
                    { title = "roslyn.nvim" }
                )
            else
                vim.list_extend(cmd, { "--extension=" .. resolved_path })
            end

            if resolved_config.args then
                local resolved_args = type(resolved_config.args) == "function" and resolved_config.args()
                    or resolved_config.args
                if resolved_args then
                    vim.list_extend(cmd, resolved_args)
                end
            end
        end
    end

    return cmd
end

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs", "razor" },
    cmd = function(dispatchers, config)
        return vim.lsp.rpc.start(get_default_cmd(), dispatchers, {
            cwd = config.cmd_cwd,
            env = config.cmd_env,
            detached = config.detached,
        })
    end,
    cmd_env = {
        Configuration = vim.env.Configuration or "Debug",
        -- Fixes LSP navigation in decompiled files for systems with symlinked TMPDIR (macOS)
        TMPDIR = vim.env.TMPDIR and vim.fn.resolve(vim.env.TMPDIR) or nil,
    },
    capabilities = {
        workspace = {
            -- support refreshing source generated documents
            textDocumentContent = {
                dynamicRegistration = true,
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        if require("roslyn.config").get().lock_target and vim.g.roslyn_nvim_selected_solution then
            local root_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
            on_dir(root_dir)
            return
        end

        -- For source-generated files, use the root_dir from the existing client
        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        if buf_name:match("^roslyn%-source%-generated://") then
            local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if existing_client and existing_client.config.root_dir then
                on_dir(existing_client.config.root_dir)
                return
            end
        end

        local root_dir = require("roslyn.sln.utils").root_dir(bufnr)
        on_dir(root_dir)
    end,
    on_init = {
        --- @param client vim.lsp.Client
        function(client)
            if not client.config.root_dir then
                return
            end
            require("roslyn.log").log(string.format("lsp on_init root_dir: %s", client.config.root_dir))

            local utils = require("roslyn.sln.utils")
            local on_init = require("roslyn.lsp.on_init")

            local config = require("roslyn.config").get()
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if config.lock_target and selected_solution then
                return on_init.sln(client, selected_solution)
            end

            local files = utils.find_files_with_extensions(client.config.root_dir, { ".sln", ".slnx", ".slnf" })

            local bufnr = vim.api.nvim_get_current_buf()
            local solution = utils.predict_target(bufnr, files)
            if solution then
                return on_init.sln(client, solution)
            end

            local csproj = utils.find_files_with_extensions(client.config.root_dir, { ".csproj" })
            if #csproj > 0 then
                return on_init.project(client, csproj)
            end

            if selected_solution then
                return on_init.sln(client, selected_solution)
            end
        end,
    },
    on_exit = {
        function(_, _, client_id)
            require("roslyn.store").set(client_id, nil)
            vim.schedule(function()
                require("roslyn.roslyn_emitter").emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
    commands = require("roslyn.lsp.commands"),
    handlers = require("roslyn.lsp.handlers"),
}
