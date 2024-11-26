local M = {}

---@class InternalRoslynNvimConfig
---@field filewatching boolean
---@field exe string[]
---@field args string[]
---@field config vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field broad_search boolean
---@field lock_target boolean

---@class RoslynNvimConfig
---@field filewatching? boolean
---@field exe? string|string[]
---@field args? string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field broad_search? boolean
---@field lock_target? boolean

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@return lsp.ClientCapabilities
local function default_capabilities()
    local ok, cmp = pcall(require, "cmp_nvim_lsp")
    local default = vim.lsp.protocol.make_client_capabilities()
    return ok and vim.tbl_deep_extend("force", default, cmp.default_capabilities()) or default
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

---@param config? RoslynNvimConfig
---@return InternalRoslynNvimConfig
function M.setup(config)
    try_setup_mason()

    ---@type InternalRoslynNvimConfig
    local default_config = {
        filewatching = true,
        exe = default_exe(),
        args = { "--logLevel=Information", "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()) },
        ---@diagnostic disable-next-line: missing-fields
        config = {
            capabilities = default_capabilities(),
        },
        choose_sln = nil,
        ignore_sln = nil,
        broad_search = false,
        lock_target = false,
    }

    local roslyn_config = vim.tbl_deep_extend("force", default_config, config or {})
    roslyn_config.exe = type(roslyn_config.exe) == "string" and { roslyn_config.exe } or roslyn_config.exe

    -- HACK: Enable filewatching to later just not watch any files
    -- This is to not make the server watch files and make everything super slow in certain situations
    if not roslyn_config.filewatching then
        roslyn_config.config.capabilities = vim.tbl_deep_extend("force", roslyn_config.config.capabilities, {
            workspace = {
                didChangeWatchedFiles = {
                    dynamicRegistration = true,
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
