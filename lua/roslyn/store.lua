local M = {}

local solutions = {}

---@param bufnr integer
---@param solution? string
function M.set(bufnr, solution)
    solutions[bufnr] = solution
    vim.g.roslyn_nvim_selected_solution = solution
end

---@param bufnr integer
function M.get(bufnr)
    return solutions[bufnr]
end

return M
