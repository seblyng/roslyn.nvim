local M = {}

---@class InternalRoslynNvimConfig
---@field filewatching "auto" | "off" | "roslyn"
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search boolean
---@field lock_target boolean

---@class RoslynNvimConfig
---@field filewatching? boolean | "auto" | "off" | "roslyn"
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search? boolean
---@field lock_target? boolean

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@return string[]?
local function default_cmd()
    local data = vim.fn.stdpath("data") --[[@as string]]

    local mason_path = vim.fs.joinpath(data, "mason", "bin", "roslyn")
    local mason_installation = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_installation) == nil then
        return nil
    end

    return {
        mason_installation,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        "--stdio",
    }
end

local function try_setup_mason()
    local ok, mason = pcall(require, "mason")
    if not ok then
        return
    end

    local registry = "github:Crashdummyy/mason-registry"
    local settings = require("mason.settings")

    local registries = vim.deepcopy(settings.current.registries)
    if not vim.list_contains(registries, registry) then
        table.insert(registries, registry)
    end

    if mason.has_setup then
        require("mason-registry.sources").set_registries(registries)
    else
        -- HACK: Insert the registry into the default registries
        -- If the user calls setup and specifies the `registries` themselves
        -- this will not work. However, if they do that, they should also
        -- just provide the registry themselves
        table.insert(settings._DEFAULT_SETTINGS.registries, registry)
    end
end

---@type InternalRoslynNvimConfig
local roslyn_config = {
    filewatching = "auto",
    choose_sln = nil,
    ignore_sln = nil,
    choose_target = nil,
    ignore_target = nil,
    broad_search = false,
    lock_target = false,
}

function M.get()
    return roslyn_config
end

-- HACK: Enable or disable filewatching based on config options
-- `off` enables filewatching but just ignores all files to watch at a later stage
-- `roslyn` disables filewatching to force the server to take care of this
---@param default vim.lsp.Config
local function resolve_filewatching_capabilities(default)
    if roslyn_config.filewatching == "off" or roslyn_config.filewatching == "roslyn" then
        return {
            didChangeWatchedFiles = {
                dynamicRegistration = roslyn_config.filewatching == "off",
            },
        }
    else
        return default.capabilities and default.capabilities.workspace or nil
    end
end

local function handle_deprecated_options()
    ---@diagnostic disable-next-line: undefined-field
    local legacy_config = roslyn_config.config

    if legacy_config then
        vim.notify(
            "The `config` option is deprecated. Use `vim.lsp.config` instead",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
        vim.lsp.config.roslyn = vim.tbl_deep_extend("force", vim.lsp.config.roslyn or {}, legacy_config)
    end

    ---@diagnostic disable-next-line: undefined-field
    local exe = roslyn_config.exe
    ---@diagnostic disable-next-line: undefined-field
    local args = roslyn_config.args

    if exe then
        if args then
            vim.notify(
                "The `args` option is deprecated. Use `vim.lsp.config.roslyn.cmd` instead",
                vim.log.levels.WARN,
                { title = "roslyn.nvim" }
            )
        end

        args = args and args
            or {
                "--logLevel=Information",
                "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
                "--stdio",
            }

        vim.notify(
            "The `exe` option is deprecated. Use `vim.lsp.config.roslyn.cmd` instead",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )

        exe = type(exe) == "string" and { exe } or exe
        vim.lsp.config.roslyn = vim.tbl_deep_extend("force", vim.lsp.config.roslyn or {}, {
            cmd = vim.list_extend(vim.deepcopy(exe), vim.deepcopy(args)),
        })
    end
end

---@param user_config? RoslynNvimConfig
---@return InternalRoslynNvimConfig
function M.setup(user_config)
    try_setup_mason()

    roslyn_config = vim.tbl_deep_extend("force", roslyn_config, user_config or {})

    handle_deprecated_options()

    local config = vim.lsp.config.roslyn or {}

    vim.lsp.config.roslyn = vim.tbl_deep_extend("force", config, {
        cmd = config and config.cmd or default_cmd(),
        capabilities = {
            textDocument = {
                diagnostic = {
                    dynamicRegistration = true,
                },
            },
            workspace = resolve_filewatching_capabilities(config),
        },
        -- HACK: Doesn't show any diagnostics if we do not set this to true
        handlers = {
            ["client/registerCapability"] = function(err, res, ctx)
                if roslyn_config.filewatching == "off" then
                    for _, reg in ipairs(res.registrations) do
                        if reg.method == "workspace/didChangeWatchedFiles" then
                            reg.registerOptions.watchers = {}
                        end
                    end
                end
                return vim.lsp.handlers["client/registerCapability"](err, res, ctx)
            end,
        },
    })

    return roslyn_config
end

return M
