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

function M.check()
    vim.health.start("roslyn.nvim: Requirements")

    local v = vim.version()
    if v.major == 0 and v.minor >= 11 then
        vim.health.ok("Neovim >= 0.11")
    else
        vim.health.error(
            "Neovim >= 0.11 is required",
            "Please upgrade to Neovim 0.11 or later. See https://github.com/neovim/neovim/releases"
        )
    end

    if vim.fn.executable("dotnet") == 1 then
        vim.health.ok("dotnet: found")
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

    vim.health.start("roslyn.nvim: Solution Detection")

    if vim.g.roslyn_nvim_selected_solution then
        vim.health.ok(string.format("Selected solution: %s", vim.g.roslyn_nvim_selected_solution))
    else
        vim.health.info("No solution selected")
    end
end

return M
