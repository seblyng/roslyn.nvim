local M = {}

--- Setup RPC wrapper to prevent duplicate textDocument/didOpen notifications
--- This fixes crashes when switching buffers via Telescope/Neotree
---@param client vim.lsp.Client
local function setup_didopen_guard(client)
    -- Skip if already guarded
    if client._roslyn_didopen_guard then
        return
    end
    client._roslyn_didopen_guard = true

    local opened_uris = {}
    local orig_notify = client.rpc.notify
    client.rpc.notify = function(method, params)
        if method == "textDocument/didOpen" then
            local uri = params and params.textDocument and params.textDocument.uri
            if uri then
                if opened_uris[uri] then
                    -- Duplicate didOpen detected - block it
                    return
                end
                opened_uris[uri] = true
            end
        elseif method == "textDocument/didClose" then
            local uri = params and params.textDocument and params.textDocument.uri
            if uri then
                opened_uris[uri] = nil
            end
        end
        return orig_notify(method, params)
    end
end

function M.sln(client, solution)
    setup_didopen_guard(client)
    require("roslyn.store").set(client.id, solution)

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
            client_id = client.id,
        },
    })
end

function M.project(client, projects)
    setup_didopen_guard(client)
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
            client_id = client.id,
        },
    })
end

return M
