local log = require("roslyn.log")

local M = {}

M.solution_extensions = { sln = true, slnx = true, slnf = true }
M.project_extensions = { csproj = true }

local target_extensions = vim.tbl_extend("force", M.solution_extensions, M.project_extensions)
local ignored_dirs = { obj = true, bin = true, [".git"] = true }

---@param name string
---@param extensions table<string, boolean>
---@return boolean
local function has_extension(name, extensions)
    return extensions[vim.fs.ext(name)] == true
end

---@param dir string
---@param extensions table<string, boolean>
---@param opts? table
---@return string[]
local function find_files(dir, extensions, opts)
    local files = {}

    for name, type in vim.fs.dir(dir, opts) do
        if type == "file" and has_extension(name, extensions) then
            files[#files + 1] = vim.fs.normalize(vim.fs.joinpath(dir, name))
        end
    end

    return files
end

---@param bufnr number
---@param extensions table<string, boolean>
---@param limit? number
---@return string[]
local function find_upward(bufnr, extensions, limit)
    local path = vim.api.nvim_buf_get_name(bufnr)
    return vim.fs.find(function(name)
        return has_extension(name, extensions)
    end, { upward = true, path = path, limit = limit })
end

---@param dir string
---@return string[] solutions, string[] projects
function M.find_target_files(dir)
    local solutions = {}
    local projects = {}

    log.log(string.format("find_target_files dir: %s, extensions: %s", dir, vim.inspect(target_extensions)))

    for _, file in ipairs(find_files(dir, target_extensions)) do
        if has_extension(file, M.project_extensions) then
            projects[#projects + 1] = file
        else
            solutions[#solutions + 1] = file
        end
    end

    return solutions, projects
end

---@param bufnr number
---@return string?
function M.find_project(bufnr)
    return find_upward(bufnr, M.project_extensions)[1]
end

---@param bufnr number
---@return string[]
function M.find_solutions(bufnr)
    local results = find_upward(bufnr, M.solution_extensions, math.huge)
    log.log(string.format("find_solutions found: %s", vim.inspect(results)))
    return results
end

---@param bufnr number
---@return string?
local function resolve_broad_search_root(bufnr)
    local solutions = M.find_solutions(bufnr)
    local sln_root = solutions[#solutions] and vim.fs.dirname(solutions[#solutions])

    local git_root = vim.fs.root(bufnr, ".git")
    if not (sln_root and git_root) then
        return sln_root or git_root
    end

    return sln_root:find(git_root, 1, true) and git_root or sln_root
end

---@param bufnr number
---@return string[]
function M.find_solutions_broad(bufnr)
    local root = resolve_broad_search_root(bufnr)
    if not root then
        return {}
    end

    local skip = function(dir)
        return not ignored_dirs[vim.fs.basename(dir)]
    end

    local slns = find_files(root, M.solution_extensions, { depth = math.huge, skip = skip })

    log.log(string.format("find_solutions_broad root: %s, found: %s", root, vim.inspect(slns)))
    return slns
end

---@param bufnr number
---@return string[]
function M.find_solutions_for_buffer(bufnr)
    local config = require("roslyn.config").get()
    return config.broad_search and M.find_solutions_broad(bufnr) or M.find_solutions(bufnr)
end

return M
