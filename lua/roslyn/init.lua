local M = {}

---@param config? RoslynNvimConfig
function M.setup(config)
    require("roslyn.config").setup(config)
    vim.lsp.enable("roslyn")
end

return M
