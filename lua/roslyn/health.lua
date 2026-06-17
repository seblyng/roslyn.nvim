local M = {}
function M.check()
    vim.health.start("roslyn.nvim: Requirements")

    local v = vim.version()
    if v.major > 0 or (v.major == 0 and v.minor >= 12) then
        vim.health.ok("Neovim >= 0.12")
    else
        vim.health.error(
            "Neovim >= 0.12 is required",
            "Please upgrade to Neovim 0.12 or later. See https://github.com/neovim/neovim/releases"
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

    local found = require("roslyn.utils").get_roslyn_lsp_path()
    if found then
        vim.health.ok(string.format("found %s", found))
    else
        vim.health.error("Roslyn language server not found", {
            "Install via Mason: :MasonInstall roslyn",
            "Or install as a .NET global tool: dotnet tool install -g Microsoft.CodeAnalysis.LanguageServer",
            "Or follow manual installation instructions at https://github.com/seblj/roslyn.nvim#-installation",
        })
    end

    vim.health.start("roslyn.nvim: Roslyn extensions:")
    local config = require("roslyn.config").get()

    local roslyn_extensions = require("roslyn.config").get().extensions or {}

    local ext_count = 0
    for ext_name, extension in pairs(roslyn_extensions) do
        vim.health.start(string.format("'%s'", ext_name))
        ext_count = ext_count + 1

        if extension.enabled then
            vim.health.ok("Enabled")
            local resolved_config = type(extension.config) == "function" and extension.config() or extension.config
            local resolved_path = type(resolved_config.path) == "function" and resolved_config.path()
                or resolved_config.path

            if not resolved_path then
                vim.health.warn(string.format("Resolved path is empty "))
            else
                local stat = vim.uv.fs_stat(resolved_path)
                local is_file = stat and stat.type == "file"
                if is_file then
                    vim.health.ok(string.format("Resolved path: '%s' (file exists)", resolved_path))
                else
                    vim.health.warn(string.format("Resolved path: '%s' (file does not exist)", resolved_path))
                end
            end

            local resolved_args = type(resolved_config.args) == "function" and resolved_config.args()
                or resolved_config.args
            if resolved_args then
                vim.health.ok(string.format("Resolved args:\n%s", table.concat(resolved_args, "\n")))
            else
                vim.health.info("No args provided for this extension")
            end
        else
            vim.health.info("Disabled")
        end
    end

    if ext_count == 0 then
        vim.health.info("No roslyn extensions configured")
    end

    vim.health.start("roslyn.nvim: Complementary language servers")

    if vim.fn.executable("vscode-html-language-server") == 1 then
        vim.health.ok("vscode-html-language-server: found")
    else
        vim.health.warn("vscode-html-language-server not found", {
            "Razor/Blazor HTML support will be limited.",
            "Install the html-lsp package via Mason.",
        })
    end

    if vim.lsp.config.html then
        vim.health.ok("html-lsp client: configured")
    else
        vim.health.warn("html-lsp client not configured", {
            "Razor/Blazor html support will be limited.",
            "Configure the html-lsp client for full Razor/Blazor support.",
        })
    end

    vim.health.start("roslyn.nvim: File Watching Configuration")
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

    local selected_solution = require("roslyn.store").get_selected_target()
    if selected_solution then
        vim.health.ok(string.format("Selected solution: %s", selected_solution))
    else
        vim.health.info("No solution selected")
    end
end

return M
