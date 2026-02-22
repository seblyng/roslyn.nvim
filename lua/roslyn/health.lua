local M = {}

---@return string[]
local function get_roslyn_executables()
    local sysname = vim.uv.os_uname().sysname:lower()
    local iswin = not not (sysname:find("windows") or sysname:find("mingw"))
    local roslyn_bin = iswin and "roslyn.cmd" or "roslyn"
    local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", roslyn_bin)

    return {
        mason_bin,
        roslyn_bin,
        "Microsoft.CodeAnalysis.LanguageServer",
    }
end

local function find_razor_extension_path()
    -- Fallback in case mason is lazy loaded or MASON env var is just not set
    local expanded_mason = vim.fn.expand("$MASON")
    local mason = expanded_mason == "$MASON" and vim.fs.joinpath(vim.fn.stdpath("data"), "mason") or expanded_mason
    local mason_packages = vim.fs.joinpath(mason, "packages")

    local stable_path = vim.fs.joinpath(mason_packages, "roslyn", "libexec", ".razorExtension")
    if vim.fn.isdirectory(stable_path) == 1 then
        return stable_path
    end

    -- TODO: Once the .razorExtension moves to the stable roslyn package, remove this
    local unstable_path = vim.fs.joinpath(mason_packages, "roslyn-unstable", "libexec", ".razorExtension")
    if vim.fn.isdirectory(unstable_path) == 1 then
        return unstable_path
    end

    return nil
end

function M.check()
    vim.health.start("roslyn.nvim: Requirements")

    local v = vim.version()
    if v.major > 0 or (v.major == 0 and v.minor >= 11) then
        vim.health.ok("Neovim >= 0.11")
    else
        vim.health.error(
            "Neovim >= 0.11 is required",
            "Please upgrade to Neovim 0.11 or later. See https://github.com/neovim/neovim/releases"
        )
    end

    if vim.fn.executable("dotnet") == 1 then
        local res = vim.system({ "dotnet", "--version" }):wait().stdout:gsub("%s+", "")
        local version = vim.version.parse(res)
        if not version then
            vim.health.warn(
                string.format("Failed to parse dotnet SDK version: %s", res),
                "Ensure that the .NET SDK is correctly installed from https://dotnet.microsoft.com/download"
            )
            return
        end

        if version.major >= 10 then
            vim.health.ok(string.format("dotnet SDK >= 10 (found %s)", res))
        else
            vim.health.warn(
                string.format("dotnet SDK >= 10 is recommended (found %s)", res),
                "Please upgrade the .NET SDK from https://dotnet.microsoft.com/download"
            )
        end
    else
        vim.health.error("dotnet command not found", "Install the .NET SDK from https://dotnet.microsoft.com/download")
    end

    vim.health.start("roslyn.nvim: Roslyn Language Server")

    local executables = get_roslyn_executables()
    local found_exe = vim.iter(executables):find(function(exe)
        return vim.fn.executable(exe) == 1
    end)

    if found_exe then
        vim.health.ok(string.format("%s: found", found_exe))
    else
        vim.health.error("Roslyn language server not found", {
            "Install via Mason: :MasonInstall roslyn",
            "Or follow manual installation instructions at https://github.com/seblj/roslyn.nvim#-installation",
        })
    end

    local found_extension = find_razor_extension_path()
    if found_extension then
        vim.health.ok(string.format("Razor extension: found at %s", found_extension))
    else
        vim.health.warn("Razor extension not found", {
            "Razor support will be limited.",
            "Install the roslyn package via Mason to get the Razor extension.",
        })
    end

    if vim.fn.executable("vscode-html-language-server") == 1 then
        vim.health.ok("vscode-html-language-server: found")
    else
        vim.health.warn("vscode-html-language-server not found", {
            "Razor HTML support will be limited.",
            "Install the html_lsp package via Mason to get the Razor extension.",
        })
    end

    if vim.lsp.config.html then
        vim.health.ok("html-lsp client: configured")
    else
        vim.health.warn("html-lsp client not configured", {
            "Razor HTML support will be limited.",
            "Consider configuring the html-lsp client for better Razor support.",
        })
    end

    vim.health.start("roslyn.nvim: File Watching Configuration")

    local config = require("roslyn.config").get()

    local client = vim.lsp.get_clients({ name = "roslyn" })[1]
    if not client then
        vim.health.warn("Roslyn is not running. Cannot determine file watching configuration.")
    else
        local did_change_watched = client.capabilities.workspace and client.capabilities.workspace.didChangeWatchedFiles
        local dynamic_registration = did_change_watched and did_change_watched.dynamicRegistration

        if config.filewatching == "auto" then
            if dynamic_registration == true then
                vim.health.info("File watching: auto (using Neovim's file watcher)")
            else
                vim.health.ok("File watching: auto (using Roslyn's built-in file watcher)")
            end
        elseif config.filewatching == "roslyn" then
            vim.health.ok("File watching: roslyn (using Roslyn's built-in file watcher)")
        elseif config.filewatching == "off" then
            vim.health.warn("File watching: off (disabled as a hack - all file changes ignored)")
        else
            vim.health.error(string.format("File watching: unknown value '%s'", config.filewatching))
        end
    end

    vim.health.start("roslyn.nvim: Solution Detection")

    if vim.g.roslyn_nvim_selected_solution then
        vim.health.ok(string.format("Selected solution: %s", vim.g.roslyn_nvim_selected_solution))
    else
        vim.health.info("No solution selected")
    end
end

return M
