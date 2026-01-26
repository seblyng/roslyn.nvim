local M = {}

local client_id_to_solution = {}

---@param client_id integer
---@param solution? string
function M.set(client_id, solution)
    client_id_to_solution[client_id] = solution
    vim.g.roslyn_nvim_selected_solution = solution
end

---@param client_id integer
function M.get(client_id)
    return client_id_to_solution[client_id]
end

return M
