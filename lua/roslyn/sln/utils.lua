local M = {}

--- Searches for files with a specific extension within a directory.
--- Only files matching the provided extension are returned.
---
--- @param dir string The directory path for the search.
--- @param extension string The file extension to look for (e.g., ".sln").
---
--- @return string[] List of file paths that match the specified extension.
local function find_files_with_extension(dir, extension)
    local matches = {}

    for entry, type in vim.fs.dir(dir) do
        if type == "file" and vim.endswith(entry, extension) then
            matches[#matches + 1] = vim.fs.normalize(vim.fs.joinpath(dir, entry))
        end
    end

    return matches
end

--- @param dir string
local function ignore_dir(dir)
    return dir:match("[Bb]in$")
        or dir:match("[Oo]bj$")
end

--- @param path string
--- @return string[] slns, string[] slnfs
local function find_solutions(path)
    local dirs = { path }
    local slns = {}  --- @type string[]
    local slnfs = {} --- @type string[]

    while #dirs > 0 do
        local dir = table.remove(dirs, 1)

        for other, fs_obj_type in vim.fs.dir(dir) do
            local name = vim.fs.joinpath(dir, other)

            if fs_obj_type == "file" then
                if name:match("%.sln$") then
                    slns[#slns + 1] = vim.fs.normalize(name)
                elseif name:match("%.slnf$") then
                    slnfs[#slnfs + 1] = vim.fs.normalize(name)
                end
            elseif fs_obj_type == 'directory' and not ignore_dir(name) then
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

        return name:match("%.sln$") ~= nil
    end)

    return { csproj_dir = csproj_dir, sln_dir = sln_dir, slnf_dir = slnf_dir }
end

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---@class RoslynNvimRootDir
---@field projects? RoslynNvimDirectoryWithFiles
---@field solutions? string[]
---@field solution_filters? string[]

---@param buffer integer
---@return RoslynNvimRootDir
function M.root(buffer)
    local broad_search = require("roslyn.config").get().broad_search

    local targets = find_targets(buffer)
    local sln = targets.sln_dir
    local csproj = targets.csproj_dir

    if not sln and not csproj then
        return {}
    end

    local projects = csproj and { files = find_files_with_extension(csproj, ".csproj"), directory = csproj } or nil

    if not sln then
        return {
            solutions = nil,
            projects = projects,
        }
    end


    if broad_search then
        local git_root = vim.fs.root(buffer, ".git")
        local search_root = git_root and sln:match(git_root) and git_root or sln

        local solutions, solution_filters = find_solutions(search_root)

        return {
            solutions = solutions,
            solution_filters = solution_filters,
            projects = projects,
        }
    else
        local slnf = targets.slnf_dir

        return {
            solutions = find_files_with_extension(sln, ".sln"),
            solution_filters = slnf and find_files_with_extension(slnf, ".slnf"),
            projects = projects,
        }
    end
end

---Tries to predict which solutions to use if we found some
---returning the potentially predicted solution
---Notifies the user if we still have multiple to choose from
---@param root RoslynNvimRootDir
---@return string?
function M.predict_sln_file(root)
    if not root.solutions then
        return nil
    end

    local config = require("roslyn.config").get()
    local solutions = vim.iter(root.solutions)
        :filter(function(solution)
            if config.ignore_sln and config.ignore_sln(solution) then
                return false
            end
            return not root.projects
                or vim.iter(root.projects.files):any(function(csproj_file)
                    return require("roslyn.sln.api").exists_in_solution(solution, csproj_file)
                end)
        end)
        :totable()

    if #solutions > 1 then
        local chosen = config.choose_sln and config.choose_sln(solutions) or nil
        if chosen then
            return chosen
        end

        vim.notify(
            "Multiple sln files found. Use `:Roslyn target` to select or change target for buffer",
            vim.log.levels.INFO,
            { title = "roslyn.nvim" }
        )
        return nil
    else
        return solutions[1]
    end
end

return M
