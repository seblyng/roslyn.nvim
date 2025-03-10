local M = {}

---@class InternalRoslynNvimConfig
---@field filewatching string "auto" | "off" | "roslyn"
---@field exe string[]
---@field args string[]
---@field config vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search boolean
---@field lock_target boolean

---@class RoslynNvimConfig
---@field filewatching? boolean | "auto" | "off" | "roslyn"
---@field exe? string|string[]
---@field args? string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search? boolean
---@field lock_target? boolean

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@return lsp.ClientCapabilities
local function default_capabilities()
    local cmp_ok, cmp = pcall(require, "cmp_nvim_lsp")
    local blink_ok, blink = pcall(require, "blink.cmp")
    local default = vim.lsp.protocol.make_client_capabilities()
    return cmp_ok and vim.tbl_deep_extend("force", default, cmp.default_capabilities())
        or blink_ok and vim.tbl_deep_extend("force", default, blink.get_lsp_capabilities())
        or default
end

---@return string[]
local function default_exe()
    local data = vim.fn.stdpath("data") --[[@as string]]

    local mason_path = vim.fs.joinpath(data, "mason", "bin", "roslyn")
    local mason_installation = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_installation) ~= nil then
        return { mason_installation }
    else
        return { "dotnet", vim.fs.joinpath(data, "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll") }
    end
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
    exe = default_exe(),
    args = {
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        "--stdio",
    },
    ---@diagnostic disable-next-line: missing-fields
    config = {
        capabilities = default_capabilities(),
    },
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

---@param user_config? RoslynNvimConfig
---@return InternalRoslynNvimConfig
function M.setup(user_config)
    try_setup_mason()

    roslyn_config = vim.tbl_deep_extend("force", roslyn_config, user_config or {})
    roslyn_config.exe = type(roslyn_config.exe) == "string" and { roslyn_config.exe } or roslyn_config.exe

    if roslyn_config.ignore_sln then
        vim.notify(
            "The `ignore_sln` option is deprecated. Please use `ignore_target` instead, which also receives solution filter files if present",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )

        if not roslyn_config.ignore_target then
            roslyn_config.ignore_target = roslyn_config.ignore_sln
        end
    end

    if roslyn_config.choose_sln then
        vim.notify(
            "The `choose_sln` option is deprecated. Please use `choose_target` instead, which also receives solution filter files if present",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )

        if not roslyn_config.choose_target then
            roslyn_config.choose_target = roslyn_config.choose_sln
        end
    end

    if not vim.tbl_contains(roslyn_config.args, "--stdio") then
        vim.notify(
            "roslyn.nvim requires the `--stdio` argument to be present. Please add it to your configuration",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
        table.insert(roslyn_config.args, "--stdio")
    end

    -- filewatching: replace legacy boolean value (true -> auto; false -> off)
    if type(roslyn_config.filewatching) == "boolean" then
        roslyn_config.filewatching = roslyn_config.filewatching and "auto" or "off"
        vim.notify(
            "Value of the `filewatching` option should be 'auto' (default), 'off' or 'roslyn'.",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end

    -- HACK: Enable filewatching to later just not watch any files
    -- This is to not make the server watch files and make everything super slow in certain situations
    if roslyn_config.filewatching == "off" or roslyn_config.filewatching == "roslyn" then
        roslyn_config.config.capabilities = vim.tbl_deep_extend("force", roslyn_config.config.capabilities, {
            workspace = {
                didChangeWatchedFiles = {
                    dynamicRegistration = roslyn_config.filewatching == "off",
                },
            },
        })
    end

    -- HACK: Doesn't show any diagnostics if we do not set this to true
    roslyn_config.config.capabilities = vim.tbl_deep_extend("force", roslyn_config.config.capabilities, {
        textDocument = {
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    })

    return roslyn_config
end

return M
