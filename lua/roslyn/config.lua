local M = {}

---@class RoslynExtension
---@field enabled boolean
---@field config (RoslynExtensionConfig | fun(): RoslynExtensionConfig)

---@class RoslynExtensionConfig
---@field path string?
---@field args? string[]

---@class InternalRoslynNvimConfig
---@field filewatching "auto" | "off" | "roslyn"
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search boolean
---@field lock_target boolean
---@field silent boolean
---@field debug boolean
---@field extensions? table<string, RoslynExtension>

---@class RoslynNvimConfig
---@field filewatching? boolean | "auto" | "off" | "roslyn"
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search? boolean
---@field lock_target? boolean
---@field silent? boolean
---@field debug? boolean
---@field extensions? table<string, RoslynExtension>

---@return table<string, RoslynExtension>
local function detect_legacy_razor_config()
    -- Will be removed eventually and only stays here  due to backwards compatibility.
    -- Since May 2026 ( 5.8.0-1.26262.10 ) roslyn bundles the razor extensions
    -- and does not require this setup anymore
    local razor_extension_path = require("roslyn.utils").find_razor_extension_path()
    if razor_extension_path == nil then
        return {}
    end

    return {
        razor = {
            enabled = true,
            config = {
                path = vim.fs.joinpath(razor_extension_path, "Microsoft.VisualStudioCode.RazorExtension.dll"),
                args = {
                    "--razorSourceGenerator="
                        .. vim.fs.joinpath(razor_extension_path, "Microsoft.CodeAnalysis.Razor.Compiler.dll"),
                    "--razorDesignTimePath=" .. vim.fs.joinpath(
                        razor_extension_path,
                        "Targets",
                        "Microsoft.NET.Sdk.Razor.DesignTime.targets"
                    ),
                },
            },
        },
    }
end

---@type InternalRoslynNvimConfig
local roslyn_config = {
    filewatching = "auto",
    choose_target = nil,
    ignore_target = nil,
    broad_search = false,
    lock_target = false,
    silent = false,
    debug = false,
    extensions = detect_legacy_razor_config(),
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
