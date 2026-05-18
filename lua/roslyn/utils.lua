local M = {}

function M.get_mason_path()
    -- Fallback in case mason is lazy loaded or MASON env var is just not set
    local expanded_mason = vim.fn.expand("$MASON")
    return expanded_mason == "$MASON" and vim.fs.joinpath(vim.fn.stdpath("data"), "mason") or expanded_mason
end

---@return string?
function M.get_roslyn_lsp_path()
    local sysname = vim.uv.os_uname().sysname:lower()
    local iswin = not not (sysname:find("windows") or sysname:find("mingw"))
    local language_server_bin = iswin and "roslyn-language-server.cmd" or "roslyn-language-server"

    local mason = M.get_mason_path()
    local candidates = {
        vim.fs.joinpath(mason, "bin", language_server_bin),
        language_server_bin,
    }

    for _, candidate in ipairs(candidates) do
        if vim.fn.executable(candidate) == 1 then
            return candidate
        end
    end

    return nil
end

return M
