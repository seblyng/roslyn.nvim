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

---Gets the root directory of the first project file and find all related project file to that directory
---@param buffer integer
---@return RoslynNvimDirectoryWithFiles?
function M.get_project_files(buffer)
	local directory = vim.fs.root(buffer, function(name)
		return name:match("%.csproj$") ~= nil
	end)

	if not directory then
		return nil
	end

	local files = vim.fs.find(function(name, _)
		return name:match("%.csproj$")
	end, { path = directory, limit = math.huge })

	return {
		directory = directory,
		files = files,
	}
end

--- Attempts to find `.csproj` files in the current working directory (CWD).
--- This function searches recursively through the files in the CWD.
--- If a `.csproj` file is found, it returns the directory path and a list of matching files.
--- If no `.csproj` files are found or the file is outside the CWD, `nil` is returned.
--- Falls back to normal behavior for checking solution and project files if no match is found.
---
--- @return RoslynNvimDirectoryWithFiles? A table containing the directory path and a list of found `.csproj` files, or `nil` if none are found.
function M.try_get_csproj_files()
	local cwd = assert(vim.uv.cwd())

	local csprojs = find_files_with_extension(cwd, ".csproj")

	local solutions = find_files_with_extension(cwd, ".sln")

	if #csprojs > 0 and #solutions == 0 then
		return {
			directory = cwd,
			files = csprojs,
		}
	end

	return nil
end

---Find the solution file from the current buffer.
---Recursively see if we have any other solution files, to potentially
---give the user an option to choose which solution file to use

---Broad search will search from the root directory and down to potentially
---find sln files that is not in the root directory.
---This could potentially be slow, so by default it is off

---@param buffer integer
---@param broad_search boolean
---@return string[]?
function M.get_solution_files(buffer, broad_search)
	local directory = vim.fs.root(buffer, function(name)
		return name:match("%.sln$") ~= nil
	end)

	if not directory then
		return nil
	end

	if broad_search then
		return vim.fs.find(function(name, _)
			return name:match("%.sln$")
		end, { type = "file", limit = math.huge, path = directory })
	else
		return find_files_with_extension(directory, ".sln")
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
	local csproj = M.get_project_files(buffer)
	if not csproj or #csproj.files > 1 then
		return nil
	end

	local csproj_filename = vim.fn.fnamemodify(csproj.files[1], ":t")

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

---request to workspace/didChangeWatchedFiles is sended to the server to inform the server of watched files changed
---@param uriFile string
function M.did_change_watched_file(uriFile)
	for _, client in ipairs(vim.lsp.get_active_clients()) do
		if client.name == "roslyn" then
			client.request("workspace/didChangeWatchedFiles", {
				changes = {
					{ uri = uriFile, type = 2 }
				}
			}, function(e)if e~=nil then print(e)end end)
		end
	end
end

return M
