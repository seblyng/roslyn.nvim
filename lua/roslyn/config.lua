local M = {}

---@class InternalRoslynNvimConfig
---@field filewatching "auto" | "off" | "roslyn"
---@field config vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field ignore_sln? fun(solution: string): boolean
---@field choose_target? fun(targets: string[]): string?
---@field ignore_target? fun(target: string): boolean
---@field broad_search boolean
---@field lock_target boolean

---@class RoslynNvimConfig
---@field filewatching? boolean | "auto" | "off" | "roslyn"
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

---@return string[]?
local function get_mason_exe()
    local data = vim.fn.stdpath("data") --[[@as string]]

    local mason_path = vim.fs.joinpath(data, "mason", "bin", "roslyn")
    local mason_installation = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_installation) == nil then
        return nil
    end

    return { mason_installation }
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
    ---@diagnostic disable-next-line: missing-fields
    config = {
        capabilities = default_capabilities(),
        cmd_env = {
            Configuration = vim.env.Configuration or "Debug",
        },
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

---@param user_config RoslynNvimConfig
local function deprecate_args(user_config)
    ---@diagnostic disable-next-line: undefined-field
    if user_config.args then
        vim.notify(
            "The `args` option is deprecated. Use `config.cmd` instead",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end
end

---@param user_config RoslynNvimConfig
---@return string[]?
local function deprecate_exe(user_config)
    ---@diagnostic disable-next-line: undefined-field
    if user_config.exe then
        vim.notify(
            "The `exe` option is deprecated. Use `config.cmd` instead",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end
end

---@param user_config RoslynNvimConfig
local function resolve_user_cmd(user_config)
    local mason_exe = get_mason_exe()

    ---@diagnostic disable-next-line: undefined-field
    local args = user_config.args and vim.deepcopy(user_config.args)
        or {
            "--logLevel=Information",
            "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
            "--stdio",
        }

    -- If we have mason then use that
    if mason_exe then
        return vim.list_extend(mason_exe, args)
    end

    ---@diagnostic disable-next-line: undefined-field
    local exe = user_config.exe and vim.deepcopy(user_config.exe) or nil
    if exe then
        exe = type(exe) == "string" and { exe } or exe
        return vim.list_extend(exe, args)
    end

    local legacy_path = vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")
    if vim.uv.fs_stat(legacy_path) then
        vim.notify(
            "The default cmd location of roslyn is deprecated.\nEither download through mason, or specify through `config.cmd` as specified in the README",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end

    return vim.list_extend({ "dotnet", legacy_path }, args)
end

---@param user_config? RoslynNvimConfig
---@return InternalRoslynNvimConfig
function M.setup(user_config)
    try_setup_mason()

    user_config = user_config or {}
    user_config.config = user_config.config or {}

    deprecate_args(user_config)
    deprecate_exe(user_config)

    if not user_config.config.cmd then
        user_config.config.cmd = user_config.config.cmd or resolve_user_cmd(user_config)
    end

    roslyn_config = vim.tbl_deep_extend("force", roslyn_config, user_config)

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
