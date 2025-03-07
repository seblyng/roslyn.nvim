local M = {}

--- Searches for files with a specific extension within a directory.
--- Only files matching the provided extension are returned.
---
--- @param dir string The directory path for the search.
--- @param extensions string[] The file extensions to look for (e.g., ".sln").
---
--- @return string[] List of file paths that match the specified extension.
local function find_files_with_extensions(dir, extensions)
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

--- @param dir string
local function ignore_dir(dir)
    return dir:match("[Bb]in$") or dir:match("[Oo]bj$")
end

--- @param path string
--- @return string[] slns, string[] slnfs
local function find_solutions(path)
    local dirs = { path }
    local slns = {} --- @type string[]
    local slnfs = {} --- @type string[]

    while #dirs > 0 do
        local dir = table.remove(dirs, 1)

        for other, fs_obj_type in vim.fs.dir(dir) do
            local name = vim.fs.joinpath(dir, other)

            if fs_obj_type == "file" then
                if name:match("%.sln$") or name:match("%.slnx$") then
                    slns[#slns + 1] = vim.fs.normalize(name)
                elseif name:match("%.slnf$") then
                    slnfs[#slnfs + 1] = vim.fs.normalize(name)
                end
            elseif fs_obj_type == "directory" and not ignore_dir(name) then
                dirs[#dirs + 1] = name
            end
        end
    end

    return slns, slnfs
end

--- @class FindTargetsResult
--- @field csproj_dir string?
--- @field sln_dir string?
--- @field slnf_dir string?

--- Searches for the directory of a project and/or solution to use for the buffer.
---@param buffer integer
---@return FindTargetsResult
local function find_targets(buffer)
    -- We should always find csproj/slnf files "on the way" to the solution file,
    -- so walk once towards the solution, and capture them as we go by.
    local csproj_dir = nil
    local slnf_dir = nil

    local sln_dir = vim.fs.root(buffer, function(name, path)
        if not csproj_dir and name:match("%.csproj$") then
            csproj_dir = path
        end

        if not slnf_dir and name:match("%.slnf$") then
            slnf_dir = path
        end

        return name:match("%.sln$") ~= nil or name:match("%.slnx$")
    end)

    return { csproj_dir = csproj_dir, sln_dir = sln_dir, slnf_dir = slnf_dir }
end

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---@class RoslynNvimRootDir
---@field projects? RoslynNvimDirectoryWithFiles
---@field solutions string[]
---@field solution_filters string[]

---@param buffer integer
---@return RoslynNvimRootDir
function M.root(buffer)
    local targets = find_targets(buffer)
    if not targets.csproj_dir then
        return {
            solution_filters = {},
            solutions = {},
            projects = nil,
        }
    end

    local projects = {
        files = find_files_with_extensions(targets.csproj_dir, { ".csproj" }),
        directory = targets.csproj_dir,
    }

    local sln = targets.sln_dir
    local slnf = targets.slnf_dir

    if not require("roslyn.config").get().broad_search then
        return {
            solutions = sln and find_files_with_extensions(sln, { ".sln", ".slnx" }) or {},
            solution_filters = slnf and find_files_with_extensions(slnf, { ".slnf" }) or {},
            projects = projects,
        }
    end

    local git_root = vim.fs.root(buffer, ".git")
    if not sln and not git_root then
        return {
            solutions = {},
            solution_filters = {},
            projects = projects,
        }
    end

    local search_root
    if sln and git_root then
        search_root = git_root and sln:find(git_root, 1, true) and git_root or sln
    else
        search_root = sln or git_root --[[@as string]]
    end

    local solutions, solution_filters = find_solutions(search_root)

    return {
        solutions = solutions,
        solution_filters = solution_filters,
        projects = projects,
    }
end

---Tries to predict which target to use if we found some
---returning the potentially predicted target
---@param root RoslynNvimRootDir
---@return boolean multiple, string? predicted_target
function M.predict_target(root)
    local config = require("roslyn.config").get()
    local sln_api = require("roslyn.sln.api")

    local filtered_targets = vim.iter({ root.solutions, root.solution_filters })
        :flatten()
        :filter(function(target)
            if config.ignore_target and config.ignore_target(target) then
                return false
            end

            return not root.projects
                or vim.iter(root.projects.files):any(function(csproj_file)
                    return sln_api.exists_in_target(target, csproj_file)
                end)
        end)
        :totable()

    if #filtered_targets > 1 then
        local chosen = config.choose_target and config.choose_target(filtered_targets)

        if chosen then
            return false, chosen
        end

        return true, nil
    else
        return false, filtered_targets[1]
    end
end

return M
