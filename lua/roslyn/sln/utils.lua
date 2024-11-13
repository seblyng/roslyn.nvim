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

    local projects = csproj
            and {
                files = find_files_with_extension(csproj, ".csproj"),
                directory = csproj,
            }
        or nil

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

--- Find a path to sln file that is likely to be the one that the current buffer
--- belongs to. Ability to predict the right sln file automates the process of starting
--- LSP, without requiring the user to invoke CSTarget each time the solution is open.
--- The prediction assumes that the nearest csproj file (in one of parent dirs from buffer)
--- should be a part of the sln file that the user intended to open.
---@param buffer integer
---@param sln_files string[]
---@return string?
function M.predict_sln_file(buffer, sln_files)
    local directory = vim.fs.root(buffer, function(name)
        return name:match("%.csproj$") ~= nil
    end)

    if not directory then
        return nil
    end

    local files = vim.fs.find(function(name, _)
        return name:match("%.csproj$")
    end, { path = directory })

    if not files then
        return nil
    end

    local csproj_filename = vim.fn.fnamemodify(files[1], ":t")

    -- Look for a solution file that contains the name of the project
    -- Predict that to be the "correct" solution file if we find the project name
    for _, file_path in ipairs(sln_files) do
        local file = io.open(file_path, "r")

        if not file then
            return nil
        end

        local content = file:read("*a")
        file:close()

        if content:find(csproj_filename, 1, true) then
            return file_path
        end
    end

    return nil
end

return M
