local M = {}

local client_id_to_solution = {}
local client_id_to_start_time = {}

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

---@param client_id integer
function M.set_init_start(client_id)
    client_id_to_start_time[client_id] = vim.uv.now()
end

---@param client_id integer
---@return integer? milliseconds since init start, or nil if not recorded
function M.get_init_elapsed_ms(client_id)
    local start = client_id_to_start_time[client_id]
    if start then
        return vim.uv.now() - start
    end
end

return M
