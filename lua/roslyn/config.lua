local M = {}

---@class InternalRoslynNvimConfig
---@field filewatching "auto" | "off" | "roslyn"
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search boolean
---@field lock_target boolean
---@field silent boolean
---@field debug boolean
---@field analyzer_assemblies string[]

---@class RoslynNvimConfig
---@field filewatching? boolean | "auto" | "off" | "roslyn"
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search? boolean
---@field lock_target? boolean
---@field silent? boolean
---@field debug? boolean
---@field analyzer_assemblies? string[]

---@type InternalRoslynNvimConfig
local roslyn_config = {
    filewatching = "auto",
    choose_target = nil,
    ignore_target = nil,
    broad_search = false,
    lock_target = false,
    silent = false,
    debug = false,
    analyzer_assemblies = {},
}

function M.get()
    return roslyn_config
end

---@param user_config? RoslynNvimConfig
---@return InternalRoslynNvimConfig
function M.setup(user_config)
    roslyn_config = vim.tbl_deep_extend("force", roslyn_config, user_config or {})

    -- HACK: Enable or disable filewatching based on config options
    -- `off` enables filewatching but just ignores all files to watch at a later stage
    -- `roslyn` disables filewatching to force the server to take care of this
    if roslyn_config.filewatching == "off" or roslyn_config.filewatching == "roslyn" then
        vim.lsp.config("roslyn", {
            -- HACK: Set filewatching capabilities here based on filewatching option to the plugin
            capabilities = {
                workspace = {
                    didChangeWatchedFiles = {
                        dynamicRegistration = roslyn_config.filewatching == "off",
                    },
                },
            },
        })
    end

    return roslyn_config
end

return M
