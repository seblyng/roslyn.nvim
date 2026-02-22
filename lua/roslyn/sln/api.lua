local M = {}

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

--- Attempts to extract the project path from a line in a solution file
---@param line string
---@param target string
---@return string? path The path to the project file
local function sln_match(line, target)
    local ext = vim.fn.fnamemodify(target, ":e")

    if ext == "sln" then
        local id, name, path = line:match('Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"')
        if id and name and path and path:match("%.csproj$") then
            return path
        end
    elseif ext == "slnx" then
        local path = line:match('<Project Path="([^"]+)"')
        if path and path:match("%.csproj$") then
            return path
        end
    elseif ext == "slnf" then
        return line:match('"(.*%.csproj)"')
    else
        error(string.format("Unknown extension `%s` for solution: `%s`", ext, target))
    end
end

---@param target string Path to solution or solution filter file
---@return string[] Table of projects in given solution
function M.projects(target)
    local file = io.open(target, "r")
    if not file then
        return {}
    end

    local paths = {}

    for line in file:lines() do
        local path = sln_match(line, target)
        if path then
            local normalized_path = iswin and path or path:gsub("\\", "/")
            local dirname = vim.fs.dirname(target)
            local fullpath = vim.fs.joinpath(dirname, normalized_path)
            local normalized = vim.fs.normalize(fullpath)
            table.insert(paths, normalized)
        end
    end

    file:close()

    return paths
end

---Checks if a project is part of a solution/solution filter or not
---@param target string Path to the solution or solution filter
---@param project string Full path to the project's csproj file
---@return boolean
function M.exists_in_target(target, project)
    return vim.list_contains(M.projects(target), project)
end

return M
