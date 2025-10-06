local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

-- Default to roslyn presumably installed by mason if found.
-- Fallback to the same default as `nvim-lspconfig`
local function get_default_cmd()
    local roslyn_bin = iswin and "roslyn.cmd" or "roslyn"
    local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", roslyn_bin)

    local exe = vim.fn.executable(mason_bin) == 1 and mason_bin
        or vim.fn.executable(roslyn_bin) == 1 and roslyn_bin
        or "Microsoft.CodeAnalysis.LanguageServer"

    return {
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.log.get_filename()),
        "--stdio",
    }
end

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs" },
    cmd = get_default_cmd(),
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
        local buf_name = vim.api.nvim_buf_get_name(bufnr)

        local config = require("roslyn.config")
        if config.get().lock_target and vim.g.roslyn_nvim_selected_solution then
            local root_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
            on_dir(root_dir)
            return
        end

        -- For source-generated files, use the root_dir from the existing client
        if buf_name:match("^roslyn%-source%-generated://") then
            local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if existing_client and existing_client.config.root_dir then
                require("roslyn.log").log(
                    string.format("lsp root_dir for source-generated file: %s", existing_client.config.root_dir)
                )
                on_dir(existing_client.config.root_dir)
                return
            end
        end

        local utils = require("roslyn.sln.utils")
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
