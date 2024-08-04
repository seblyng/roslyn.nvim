---@param file_paths string[]
---@param search_string string
---@return string?
local function get_filepath_containing_string(file_paths, search_string)
    for _, file_path in ipairs(file_paths) do
        local file = io.open(file_path, "r")

        if not file then
            return nil
        end

        local content = file:read("*a")
        file:close()

        if content:find(search_string, 1, true) then
            return file_path
        end
    end

    return nil
end

local M = {}

---@class RoslynNvimDirectoryWithFiles
---@field directory string
---@field files string[]

---Gets the directory containing `ext`, and all the files in that directory with `ext`
---@param buffer integer
---@param ext "sln" | "csproj"
---@return RoslynNvimDirectoryWithFiles?
function M.get_directory_with_files(buffer, ext)
    local directory = vim.fs.root(buffer, function(name)
        return name:match(string.format("%%.%s$", ext)) ~= nil
    end)

    if not directory then
        return nil
    end

    -- Probably redundant check, but doesn't hurt
    local files = vim.fn.glob(vim.fs.joinpath(directory, string.format("*.%s", ext)), true, true)
    if not files then
        return nil
    end

    return {
        directory = directory,
        files = files,
    }
end

--- Find a path to sln file that is likely to be the one that the current buffer
--- belongs to. Ability to predict the right sln file automates the process of starting
--- LSP, without requiring the user to invoke CSTarget each time the solution is open.
--- The prediction assumes that the nearest csproj file (in one of parent dirs from buffer)
--- should be a part of the sln file that the user intended to open.
---@param buffer integer
---@param sln RoslynNvimDirectoryWithFiles
---@return string?
function M.predict_sln_file(buffer, sln)
    local csproj = M.get_directory_with_files(buffer, "csproj")
    if not csproj or #csproj.files > 1 then
        return nil
    end

    local csproj_filename = vim.fn.fnamemodify(csproj.files[1], ":t")

    return get_filepath_containing_string(sln.files, csproj_filename)
end

return M
