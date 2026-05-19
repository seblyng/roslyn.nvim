local log = require("roslyn.log")

local M = {}

--- Searches for files with specific extensions within a directory.
---@param dir string
---@param extensions string[]
---@return string[]
function M.find_files_with_extensions(dir, extensions)
    local matches = {}

    log.log(string.format("find_files_with_extensions dir: %s, extensions: %s", dir, vim.inspect(extensions)))

    for entry, type in vim.fs.dir(dir) do
        if type == "file" then
            for _, ext in ipairs(extensions) do
                if vim.endswith(entry, ext) then
                    matches[#matches + 1] = vim.fs.normalize(vim.fs.joinpath(dir, entry))
                end
            end
        end
    end

    return matches
end

---@param paths string[]
---@return string?
local function get_shortest_path(paths)
    local shortest = nil
    for _, path in ipairs(paths) do
        local dir = vim.fs.dirname(path)
        if not shortest or #dir < #shortest then
            shortest = dir
        end
    end
    return shortest
end

---@param bufnr number
---@return string[]
function M.find_solutions(bufnr)
    local results = vim.fs.find(function(name)
        return name:match("%.sln$") or name:match("%.slnx$") or name:match("%.slnf$")
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr), limit = math.huge })
    log.log(string.format("find_solutions found: %s", vim.inspect(results)))
    return results
end

---@param buffer number
---@return string?
local function resolve_broad_search_root(buffer)
    local solutions = M.find_solutions(buffer)
    local sln_root = get_shortest_path(solutions)

    local git_root = vim.fs.root(buffer, ".git")
    if sln_root and git_root then
        return git_root and sln_root:find(git_root, 1, true) and git_root or sln_root
    else
        return sln_root or git_root
    end
end

local ignored_dirs = {
    "obj",
    "bin",
    ".git",
}

---@param bufnr number
---@return string[]
function M.find_solutions_broad(bufnr)
    local root = resolve_broad_search_root(bufnr)
    local dirs = { root }
    local slns = {} --- @type string[]

    while #dirs > 0 do
        local dir = table.remove(dirs, 1)

        for other, fs_obj_type in vim.fs.dir(dir) do
            local name = vim.fs.joinpath(dir, other)

            if fs_obj_type == "file" then
                if name:match("%.sln$") or name:match("%.slnx$") or name:match("%.slnf$") then
                    slns[#slns + 1] = vim.fs.normalize(name)
                end
            elseif fs_obj_type == "directory" and not vim.list_contains(ignored_dirs, vim.fs.basename(name)) then
                dirs[#dirs + 1] = name
            end
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
