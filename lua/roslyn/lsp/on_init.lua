local M = {}

function M.sln(client, solution)
    local store = require("roslyn.store")
    store.set(client.id, solution)
    store.set_init_start(client.id)

    if not require("roslyn.config").get().silent then
        local sln_name = vim.fn.fnamemodify(solution, ":t:r")
        vim.notify("Initializing\n" .. sln_name, vim.log.levels.INFO, { title = "roslyn.nvim" })
    end

    client:notify("solution/open", {
        solution = vim.uri_from_fname(solution),
    })

    vim.api.nvim_exec_autocmds("User", {
        pattern = "RoslynOnInit",
        data = {
            type = "solution",
            target = solution,
            client_id = client.id,
        },
    })
end

function M.project(client, projects)
    require("roslyn.store").set_init_start(client.id)

    if not require("roslyn.config").get().silent then
        vim.notify("Initializing project", vim.log.levels.INFO, { title = "roslyn.nvim" })
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
            client_id = client.id,
        },
    })
end

return M
