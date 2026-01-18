local M = {}

local buffer_to_solution = {}
local client_id_to_solution = {}

---@param bufnr integer
---@param client_id integer
---@param solution? string
function M.set(bufnr, client_id, solution)
    buffer_to_solution[bufnr] = solution
    client_id_to_solution[client_id] = solution
    vim.g.roslyn_nvim_selected_solution = solution
end

---@param bufnr integer
function M.get_by_bufnr(bufnr)
    return buffer_to_solution[bufnr]
end

---@param client_id integer
function M.get_by_client_id(client_id)
    return client_id_to_solution[client_id]
end

return M
