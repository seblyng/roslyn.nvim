local M = {}

function M.sln(client, solution)
    vim.g.roslyn_nvim_selected_solution = solution
    if not require("roslyn.config").get().silent then
        vim.notify("Initializing Roslyn for: " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
    end

    client:notify("solution/open", {
        solution = vim.uri_from_fname(solution),
    })

    vim.api.nvim_exec_autocmds("User", {
        pattern = "RoslynOnInit",
        data = {
            type = "solution",
            target = solution,
        },
    })
end

function M.project(client, projects)
    if not require("roslyn.config").get().silent then
        vim.notify("Initializing Roslyn for: project", vim.log.levels.INFO, { title = "roslyn.nvim" })
    end
    client:notify("project/open", {
        projects = vim.tbl_map(function(file)
            return vim.uri_from_fname(file)
        end, projects),
    })

    vim.api.nvim_exec_autocmds("User", {
        pattern = "RoslynOnInit",
        data = {
            type = "project",
            target = projects,
        },
    })
end

return M
