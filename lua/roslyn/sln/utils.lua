local api = require("roslyn.sln.api")

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

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---@class RoslynNvimRootDir
---@field projects? RoslynNvimDirectoryWithFiles
---@field solutions string[]

---@param buffer integer
---@param broad_search boolean
---@return RoslynNvimRootDir
function M.root_dir(buffer, broad_search)
    local sln = vim.fs.root(buffer, function(name)
        return name:match("%.sln$") ~= nil
    end)

    local csproj = vim.fs.root(buffer, function(name)
        return name:match("%.csproj$") ~= nil
    end)

    if not sln or not csproj then
        return {}
    end

    local projects = csproj and { files = find_files_with_extension(csproj, ".csproj"), directory = csproj } or nil

    if broad_search then
        local solutions = vim.fs.find(function(name, _)
            return name:match("%.sln$")
        end, { type = "file", limit = math.huge, path = sln })

        return {
            solutions = solutions,
            projects = projects,
        }
    else
        return {
            solutions = find_files_with_extension(sln, ".sln"),
            projects = projects,
        }
    end
end

local function multiple_solutions_notify()
    vim.notify(
        "Multiple sln files found. Use `:Roslyn target` to select or change target for buffer",
        vim.log.levels.INFO,
        { title = "roslyn.nvim" }
    )
end

local function _predict_sln_file(root, config)
    if not root.solutions then
        return nil
    end

    if root.projects then
        local solutions = vim.iter(root.solutions)
            :filter(function(it)
                return api.exists_in_solution(it, root.projects.files[1])
            end)
            :totable()

        if #solutions > 1 then
            return config.choose_sln and config.choose_sln(solutions) or multiple_solutions_notify()
        else
            return solutions[1]
        end
    else
        if #root.solutions > 1 then
            return multiple_solutions_notify()
        else
            return root.solutions[1]
        end
    end
end

---Tries to predict the correct solution file based on certain scenarios
---  - If we also a project file, find all solutions that uses the project
---    - If there is only one, then use that
---    - If there are more, let user choose with config method
---  - If we don't have project files but have solution files
---    - If there is only one, then use that
---@param root RoslynNvimRootDir
---@param config InternalRoslynNvimConfig
---@return string?
function M.predict_sln_file(root, config)
    local sln_file = _predict_sln_file(root, config)
    if sln_file and config.ignore_sln then
        if config.ignore_sln(sln_file) then
            return nil
        else
            return sln_file
        end
    else
        return sln_file
    end
end

return M
