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
---@field solutions? string[]

---@param buffer integer
---@return RoslynNvimRootDir
function M.root(buffer)
    local broad_search = require("roslyn.config").get().broad_search

    local sln = vim.fs.root(buffer, function(name)
        return name:match("%.sln$") ~= nil
    end)

    local csproj = vim.fs.root(buffer, function(name)
        return name:match("%.csproj$") ~= nil
    end)

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

        local solutions = vim.fs.find(function(name, _)
            return name:match("%.sln$")
        end, { type = "file", limit = math.huge, path = search_root })
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
