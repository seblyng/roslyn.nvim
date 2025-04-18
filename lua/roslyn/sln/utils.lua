local sln_api = require("roslyn.sln.api")

local M = {}

--- Searches for files with a specific extension within a directory.
--- Only files matching the provided extension are returned.
---
--- @param dir string The directory path for the search.
--- @param extensions string[] The file extensions to look for (e.g., ".sln").
---
--- @return string[] List of file paths that match the specified extension.
function M.find_files_with_extensions(dir, extensions)
    local matches = {}

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

---@param targets string[]
---@param csproj string
---@return string[]
local function filter_targets(targets, csproj)
    local config = require("roslyn.config").get()
    return vim.iter(targets)
        :filter(function(target)
            if config.ignore_target and config.ignore_target(target) then
                return false
            end

            return not csproj or sln_api.exists_in_target(target, csproj)
        end)
        :totable()
end

--- @param dir string
local function ignore_dir(dir)
    return dir:match("[Bb]in$") or dir:match("[Oo]bj$")
end

--- @param path string?
--- @return string[] slns
local function find_solutions(path)
    local dirs = { path }
    local slns = {} --- @type string[]

    while #dirs > 0 do
        local dir = table.remove(dirs, 1)

        for other, fs_obj_type in vim.fs.dir(dir) do
            local name = vim.fs.joinpath(dir, other)

            if fs_obj_type == "file" then
                if name:match("%.sln$") or name:match("%.slnx$") or name:match("%.slnf$") then
                    slns[#slns + 1] = vim.fs.normalize(name)
                end
            elseif fs_obj_type == "directory" and not ignore_dir(name) then
                dirs[#dirs + 1] = name
            end
        end
    end

    return slns
end

--- @class FindTargetsResult
--- @field csproj_file string?
--- @field sln_dir string?

--- Searches for the directory of a project and/or solution to use for the buffer.
---@param buffer integer
---@return FindTargetsResult
local function find_targets(buffer)
    -- We should always find csproj/slnf files "on the way" to the solution file,
    -- so walk once towards the solution, and capture them as we go by.
    local csproj_file = nil

    local sln_dir = vim.fs.root(buffer, function(name, path)
        if not csproj_file and name:match("%.csproj$") then
            csproj_file = vim.fs.joinpath(path, name)
        end

        return name:match("%.sln$") ~= nil or name:match("%.slnx$")
    end)

    return { csproj_file = csproj_file, sln_dir = sln_dir }
end

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---@class RoslynNvimRootDir
---@field projects? RoslynNvimDirectoryWithFiles
---@field solutions string[]

---@param buffer number
---@param sln string?
local function resolve_root(buffer, sln)
    local git_root = vim.fs.root(buffer, ".git")
    if sln and git_root then
        return git_root and sln:find(git_root, 1, true) and git_root or sln
    else
        return sln or git_root
    end
end

---@param bufnr integer
---@return string?
function M.root_dir(bufnr)
    local config = require("roslyn.config").get()
    local targets = find_targets(bufnr)
    if not targets.csproj_file then
        return nil
    end

    local sln = targets.sln_dir

    local solutions = require("roslyn.config").get().broad_search and find_solutions(resolve_root(bufnr, sln))
        or sln and M.find_files_with_extensions(sln, { ".sln", ".slnx", ".slnf" })
        or {}

    if #solutions == 1 then
        return vim.fs.dirname(solutions[1])
    end

    if #solutions == 0 then
        return vim.fs.dirname(targets.csproj_file)
    end

    local filtered_targets = filter_targets(solutions, targets.csproj_file)
    if #filtered_targets > 1 then
        local chosen = config.choose_target and config.choose_target(filtered_targets)
        if chosen then
            return vim.fs.dirname(chosen)
        else
            return vim.notify(
                "Multiple potential target files found. Use `:Roslyn target` to select a target.",
                vim.log.levels.INFO,
                { title = "roslyn.nvim" }
            )
        end
    else
        return vim.fs.dirname(filtered_targets[1])
    end
end

---@param bufnr number
---@param targets string[]
---@param csproj_file? string
---@return string?
function M.predict_target(bufnr, targets, csproj_file)
    local config = require("roslyn.config").get()

    local csproj = csproj_file
        or vim.fs.find(function(name)
            return name:match("%.csproj$") ~= nil
        end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr) })[1]

    local filtered_targets = filter_targets(targets, csproj)
    if #filtered_targets > 1 then
        return config.choose_target and config.choose_target(filtered_targets) or nil
    else
        return filtered_targets[1]
    end
end

return M
