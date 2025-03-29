local M = {}

---@param bufnr integer
---@param root_dir string
---@param on_init fun(client: vim.lsp.Client)
function M.start(bufnr, root_dir, on_init)
    local _on_init, _on_exit = vim.lsp.config.roslyn.on_init, vim.lsp.config.roslyn.on_exit

    vim.lsp.config("roslyn", {
        root_dir = root_dir,
        on_init = function(client, initialize_result)
            if _on_init then
                _on_init(client, initialize_result)
            end
            on_init(client)

            local lsp_commands = require("roslyn.lsp_commands")
            lsp_commands.fix_all_code_action(client)
            lsp_commands.nested_code_action(client)
            lsp_commands.completion_complex_edit()
        end,
        on_exit = function(code, signal, client_id)
            vim.g.roslyn_nvim_selected_solution = nil
            vim.schedule(function()
                require("roslyn.roslyn_emitter"):emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
            if _on_exit then
                _on_exit(code, signal, client_id)
            end
        end,
    })

    vim.lsp.start(vim.lsp.config.roslyn, { bufnr = bufnr })
end

---@param solution string
function M.on_init_sln(solution)
    return function(client)
        vim.g.roslyn_nvim_selected_solution = solution
        vim.notify("Initializing Roslyn client for " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("solution/open", {
            solution = vim.uri_from_fname(solution),
        })
    end
end

---@param files string[]
function M.on_init_project(files)
    return function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, files),
        })
    end
end

return M
