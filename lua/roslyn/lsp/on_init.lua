local M = {}

function M.sln(client, solution)
    vim.g.roslyn_nvim_selected_solution = solution
    vim.notify("Initializing Roslyn client for " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
    client:notify("solution/open", {
        solution = vim.uri_from_fname(solution),
    })
end

function M.projects(client, projects)
    vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
    client:notify("project/open", {
        projects = vim.tbl_map(function(file)
            return vim.uri_from_fname(file)
        end, projects),
    })
end

return M
