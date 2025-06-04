local utils = require("roslyn.sln.utils")

---@return string[]?
local function default_cmd()
    local sysname = vim.uv.os_uname().sysname:lower()
    local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

    local mason_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "roslyn")
    local mason_cmd = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_cmd) == nil then
        return nil
    end

    return {
        mason_cmd,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        "--stdio",
    }
end

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs" },
    cmd = default_cmd(),
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
        if root_dir then
            on_dir(root_dir)
        end
    end,
    on_init = {
        function(client)
            local on_init = require("roslyn.lsp.on_init")

            local config = require("roslyn.config").get()
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if config.lock_target and selected_solution then
                return on_init.sln(client, selected_solution)
            end

            local bufnr = vim.api.nvim_get_current_buf()
            local files = utils.find_files_with_extensions(client.config.root_dir, { ".sln", ".slnx", ".slnf" })

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
