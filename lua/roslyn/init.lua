local M = {}

---@param config? RoslynNvimConfig
function M.setup(config)
    require("roslyn.config").setup(config)
end

return M
