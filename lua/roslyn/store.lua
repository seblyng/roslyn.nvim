local M = {}

local client_id_to_solution = {}

---@param client_id integer
---@param solution? string
function M.set_client_target(client_id, solution)
    client_id_to_solution[client_id] = solution
    M.set_selected_target(solution)
end

---@param client_id integer
function M.clear_client_target(client_id)
    M.set_client_target(client_id, nil)
end

---@param client_id integer
---@return string?
function M.get_client_target(client_id)
    return client_id_to_solution[client_id]
end

---@param solution? string
function M.set_selected_target(solution)
    vim.g.roslyn_nvim_selected_solution = solution
end

---@return string?
function M.get_selected_target()
    return vim.g.roslyn_nvim_selected_solution
end

---@param bufnr integer
function M.sync_selected_target_for_buffer(bufnr)
    if require("roslyn.config").get().lock_target then
        return
    end

    local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
    if client then
        M.set_selected_target(M.get_client_target(client.id))
    end
end

return M
