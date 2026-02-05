local M = {}

function M.is_valid_dll_path(path)
    if type(path) ~= "string" then
        return false
    end

    if path:sub(-4):lower() ~= ".dll" then
        return false
    end

    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "file"
end

return M
