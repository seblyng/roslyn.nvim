local M = {}

---@param config? RoslynNvimConfig
function M.setup(config)
    local resolved = require("roslyn.config").setup(config)

    if resolved.dim_inactive_regions then
        vim.api.nvim_set_hl(0, "@lsp.type.excludedCode", { default = true, link = "DiagnosticUnnecessary" })
    end
end

return M
