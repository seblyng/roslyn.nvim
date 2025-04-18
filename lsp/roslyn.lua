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

local function on_init_sln(solution)
    return function(client)
        vim.g.roslyn_nvim_selected_solution = solution
        vim.notify("Initializing Roslyn client for " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("solution/open", {
            solution = vim.uri_from_fname(solution),
        })
    end
end

local function on_init_projects(projects)
    return function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, projects),
        })
    end
end

return {
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
        local root_dir = utils.root_dir(bufnr)
        if root_dir then
            on_dir(root_dir)
        end
    end,
    on_init = {
        function(client)
            local config = require("roslyn.config").get()
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if config.lock_target and selected_solution then
                return on_init_sln(selected_solution)(client)
            end

            local bufnr = vim.api.nvim_get_current_buf()
            local files = utils.find_files_with_extensions(client.config.root_dir, { ".sln", ".slnx", ".slnf" })

            local solution = utils.predict_target(bufnr, files)
            if solution then
                return on_init_sln(solution)(client)
            end

            local csproj = utils.find_files_with_extensions(client.config.root_dir, { ".csproj" })
            if #csproj > 0 then
                return on_init_projects(csproj)(client)
            end

            if selected_solution then
                return on_init_sln(selected_solution)(client)
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
