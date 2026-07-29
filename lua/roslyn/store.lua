local M = {}

local client_id_to_solution = {}

---@param client_id integer
---@param solution? string
function M.set(client_id, solution)
    client_id_to_solution[client_id] = solution
    M.set_selected_target(solution)
end

---@param client_id integer
---@return string?
function M.get(client_id)
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

return M
