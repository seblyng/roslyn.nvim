local M = {}

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@param solution string Path to solution
---@return string[] Table of projects in given solution
function M.projects(solution)
    local file = io.open(solution, "r")
    if not file then
        return {}
    end

    local paths = {}

    for line in file:lines() do
        local id, name, path = line:match('Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"')
        if id and name and path and path:match("%.csproj$") then
            local normalized_path = iswin and path or path:gsub("\\", "/")
            local dirname = vim.fs.dirname(solution)
            local fullpath = vim.fs.joinpath(dirname, normalized_path)
            local normalized = vim.fs.normalize(fullpath)
            table.insert(paths, normalized)
        end
    end

    file:close()

    return paths
end

---Checks if a project is part of a solution or not
---@param solution string
---@param project string Full path to the csproj file
---@return boolean
function M.exists_in_solution(solution, project)
    local projects = M.projects(solution)

    return vim.iter(projects):find(function(it)
        return it == project
    end) ~= nil
end

return M
