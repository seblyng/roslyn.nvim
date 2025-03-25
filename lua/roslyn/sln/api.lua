local M = {}

---@param file file* The file handle to the solution file
---@param solution string The path to the solution file
---@param match function A function that takes a line from the file, and returns a project path if the line contains a reference to a project file.
---@return string[] paths Paths to the projects in the solution
local function projects_core(file, solution, match)
    local paths = {}

    for line in file:lines() do
        local path = match(line, vim.fn.fnamemodify(solution, ":e"))
        if path then
            local dirname = vim.fs.dirname(solution)
            local fullpath = vim.fs.joinpath(dirname, path)
            local normalized = vim.fs.normalize(fullpath)
            table.insert(paths, normalized)
        end
    end

    return paths
end

--- Attempts to extract the project path from a line in a solution file
---@param line string
---@param type "slnx" | "sln"
---@return string? path The path to the project file
local function sln_match(line, type)
    if type == "sln" then
        local id, name, path = line:match('Project%("{(.-)}"%).*= "(.-)", "(.-)", "{.-}"')
        if id and name and path and path:match("%.csproj$") then
            return path
        end
    elseif type == "slnx" then
        local path = line:match('<Project Path="([^"]+)"')
        if path and path:match("%.csproj$") then
            return path
        end
    else
        error("Unknown type " .. type)
    end
end

--- Attempts to extract the project path from a line in a solution filter file
---@param line string
---@return string? path The path to the project file
local function slnf_match(line)
    return line:match('"(.*%.csproj)"')
end

---@param target string Path to solution or solution filter file
---@return string[] Table of projects in given solution
function M.projects(target)
    local file = io.open(target, "r")
    if not file then
        return {}
    end

    local paths = (target:match("%.sln$") or target:match("%.slnx$")) and projects_core(file, target, sln_match)
    or target:match("%.slnf$") and projects_core(file, target, slnf_match)

    file:close()

    return paths
end

---Checks if a project is part of a solution or not
---@deprecated Renamed to `exists_in_target`.
---@param solution string
---@param project string Full path to the csproj file
---@return boolean
function M.exists_in_solution(solution, project)
    vim.notify(
        "`exists_in_solution` has been renamed `exists_in_target` and may be removed in a future release",
        vim.log.levels.WARN,
        { title = "roslyn.nvim" }
    )

    local projects = M.projects(solution)

    return vim.iter(projects):find(function(it)
        return it == project
    end) ~= nil
end

---Checks if a project is part of a solution/solution filter or not
---@param target string Path to the solution or solution filter
---@param project string Full path to the project's csproj file
---@return boolean
function M.exists_in_target(target, project)
    local projects = M.projects(target)

    return vim.iter(projects):find(function(it)
        return it == project
    end) ~= nil
end

return M
