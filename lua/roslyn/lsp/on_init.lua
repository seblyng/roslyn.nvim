local M = {}

function M.sln(client, solution)
    require("roslyn.store").set_client_target(client.id, solution)

    client:notify("solution/open", {
        solution = vim.uri_from_fname(solution),
    })
end

function M.project(client, projects)
    client:notify("project/open", {
        projects = vim.tbl_map(function(file)
            return vim.uri_from_fname(file)
        end, projects),
    })
end

return M
