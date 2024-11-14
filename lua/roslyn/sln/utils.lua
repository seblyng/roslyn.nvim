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
---@field solutions? string[]

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

---Tries to predict which solutions to use if we found some
---returning the potentially predicted solution
---Notifies the user if we still have multiple to choose from
---@param root RoslynNvimRootDir
---@param config InternalRoslynNvimConfig
---@return string?
function M.predict_sln_file(root, config)
    if not root.solutions then
        return nil
    end

    local solutions = vim.iter(root.solutions)
        :filter(function(it)
            if config.ignore_sln and config.ignore_sln(it) then
                return false
            end
            return (not root.projects or api.exists_in_solution(it, root.projects.files[1]))
        end)
        :totable()

    if #solutions > 1 then
        return config.choose_sln and config.choose_sln(solutions)
            or vim.notify(
                "Multiple sln files found. Use `:Roslyn target` to select or change target for buffer",
                vim.log.levels.INFO,
                { title = "roslyn.nvim" }
            )
    else
        return solutions[1]
    end
end

return M
