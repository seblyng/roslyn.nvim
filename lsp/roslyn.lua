local utils = require("roslyn.sln.utils")

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs" },
    cmd = {
        "roslyn",
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        "--stdio",
    },
    cmd_env = {
        Configuration = vim.env.Configuration or "Debug",
    },
    capabilities = {
        textDocument = {
            -- HACK: Doesn't show any diagnostics if we do not set this to true
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        local config = require("roslyn.config")
        local solutions = config.get().broad_search and utils.find_solutions_broad(bufnr) or utils.find_solutions(bufnr)
        local root_dir = utils.root_dir(bufnr, solutions, vim.g.roslyn_nvim_selected_solution)
        require("roslyn.log").log(string.format("lsp root_dir is: %s", root_dir))
        on_dir(root_dir)
    end,
    on_init = {
        function(client)
            if not client.config.root_dir then
                return
            end
            require("roslyn.log").log(string.format("lsp on_init root_dir: %s", client.config.root_dir))

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
                return on_init.projects(client, csproj)
            end

            if selected_solution then
                return on_init.sln(client, selected_solution)
            end
        end,
    },
    on_exit = {
        function()
            vim.g.roslyn_nvim_selected_solution = nil
            vim.schedule(function()
                require("roslyn.roslyn_emitter"):emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
    commands = require("roslyn.lsp.commands"),
    handlers = require("roslyn.lsp.handlers"),
}
