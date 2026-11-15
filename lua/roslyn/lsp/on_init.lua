local M = {}

function M.sln(client, solution)
    require("roslyn.store").set(client.id, solution)

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

function M.single_file(client)
    local original = client.handlers["$/progress"]
    client.handlers["$/progress"] = function(err, params, ctx)
        original(err, params, ctx)
        if params.value and params.value.kind == "end" then
            client.handlers["$/progress"] = original
            for buf, _ in pairs(client.attached_buffers) do
                if vim.api.nvim_buf_is_loaded(buf) then
                    vim.api.nvim_exec_autocmds("LspNotify", {
                        buffer = buf,
                        data = {
                            client_id = ctx.client_id,
                            method = "textDocument/didOpen",
                            params = {},
                        },
                    })
                end
            end
        end
    end
end

return M
