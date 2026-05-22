local log = require("roslyn.log")

local M = {}

local solution_extensions = { sln = true, slnx = true, slnf = true }
local ignored_dirs = { obj = true, bin = true, [".git"] = true }

---@param name string
local function is_solution(name)
    return solution_extensions[vim.fs.ext(name)]
end

---@param dir string
---@param extensions string[]
---@return string[]
function M.find_files_with_extensions(dir, extensions)
    local matches = {}

    log.log(string.format("find_files_with_extensions dir: %s, extensions: %s", dir, vim.inspect(extensions)))

    for name, type in vim.fs.dir(dir) do
        if type == "file" and vim.tbl_contains(extensions, vim.fs.ext(name)) then
            matches[#matches + 1] = vim.fs.normalize(vim.fs.joinpath(dir, name))
        end
    end

    return matches
end

---@param bufnr number
---@return string[]
function M.find_solutions(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    local results = vim.fs.find(is_solution, { upward = true, path = path, limit = math.huge })
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

    local slns = {} --- @type string[]
    for name, fs_obj_type in vim.fs.dir(root, { depth = math.huge, skip = skip }) do
        if fs_obj_type == "file" and is_solution(name) then
            slns[#slns + 1] = vim.fs.normalize(vim.fs.joinpath(root, name))
        end
    end

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
