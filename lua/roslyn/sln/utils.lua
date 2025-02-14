local M = {}
local config = require("roslyn.config")

-- Find solution alternative section
local function debug(...)
	if config.get().debug_enabled then
		vim.notify(..., vim.log.levels.DEBUG)
	end
end

local excluded_dirs = {
	node_modules = "node_modules",
	git = ".git",
	dist = "dist",
	wwwroot = "wwwroot",
	properties = "properties",
	build = "build",
	bin = "bin",
	debug = "debug",
	obj = "obj",
}

M.is_excluded = function(name)
	for _, pattern in pairs(excluded_dirs) do
		if string.match(name:lower(), pattern) then
			return true
		end
	end
	return false
end

M.patterns = {
	sln = "%.sln[x]?$",   -- % is excape char symbol
	slnf = "%.slnf$",
	csproj = "%.csproj$",
}

M.is_start_with_symbol = function(name)
	return string.match(name, "^[^0-9A-Za-z_]") ~= nil
end

M.merge = function(table1, table2)
	local merged_table = {}
	local index = 1
	for _, value in pairs(table1) do
		table.insert(merged_table, index, value)
		index = index + 1
	end
	for _, value in pairs(table2) do
		table.insert(merged_table, index, value)
		index = index + 1
	end
	return merged_table
end

M.set_solution = function(path)
	if not path then
		path = path and path or "nil"
		vim.notify("Incorrect sln/proj file" .. path, vim.log.levels.WARN)
		return
	end

	-- Store the selected path
	vim.g.roslyn_nvim_selected_solution = path
	vim.notify("Selected: " .. path, vim.log.levels.INFO)

	-- Start lsp
	local roslyn_lsp = require("roslyn.lsp")
	local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
	roslyn_lsp.start(vim.api.nvim_get_current_buf(), sln_dir, roslyn_lsp.on_init_sln)
end

---@param current_dir string
---@return string[] slns, string[] slnfs, string[] csprojs
M.find_sln_files = function(current_dir)
	local visited_dirs = {}
	local extracted_dirs = {}

	local slns = {}      --- @type string[]
	local slnfs = {}     --- @type string[]
	local csprojs = {}   --- @type string[]

	---finds proj or sln files in the directory
	local function find_in_dir(dir)
		if not M.is_excluded(dir) then
			visited_dirs[dir] = true
		end

		visited_dirs["find_in_dir " .. dir] = true
		debug("find_in_dir " .. dir)
		local handle, err = vim.uv.fs_scandir(dir)

		if not handle then
			vim.notify("Error scanning in directory: " .. err, vim.log.levels.WARN)
			return slns, slnfs, csprojs
		end

		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				debug("find_in_dir no more files " .. dir)
				break
			end

			local full_path = vim.fs.normalize(vim.fs.joinpath(dir, name))

			if not visited_dirs[full_path] and not M.is_excluded(name) and not M.is_start_with_symbol(name) then
				if type == "file" then
					if string.match(name, M.patterns.sln) ~= nil then
						table.insert(slns, full_path)
					elseif string.match(name, M.patterns.slnf) ~= nil then
						table.insert(slnfs, full_path)
					elseif string.match(name, M.patterns.csproj) ~= nil then
						table.insert(csprojs, full_path)
					end
				elseif type == "directory" then
					table.insert(extracted_dirs, full_path)
				end
			end
			visited_dirs[full_path] = true
		end
	end

	local function search_upwards(path)
		local dir = path
		while true do
			find_in_dir(dir)
			if #slns > 0 or #slnfs > 0 then
				vim.notify("solution(s) found" .. vim.inspect(M.merge(slns, slnfs)), vim.log.levels.INFO)
				break
			end

			if #extracted_dirs > 0 then
				dir = table.remove(extracted_dirs, 1)
				debug("extracted_dirs entry used" .. dir)
			else
				local one_up_folder = vim.uv.fs_realpath(path .. "/..")         -- Move to parent directory
				debug("searching one up folder " .. one_up_folder)
				if one_up_folder == path then
					break
				end
				path = one_up_folder
				dir = one_up_folder
			end
		end
		debug(vim.inspect(visited_dirs))
	end

	search_upwards(current_dir)
	return slns, slnfs, csprojs
end

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
		if not csproj_dir and string.match(name, M.patterns.csproj) then
			csproj_dir = path
		end

		if not slnf_dir and string.match(name, M.patterns.slnf) then
			slnf_dir = path
		end

		return string.match(name, M.patterns.sln) ~= nil
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
	local broad_search = config.get().broad_search

	local targets = find_targets(buffer)
	local sln = targets.sln_dir
	local csproj = targets.csproj_dir

	if not sln and not csproj then
		return {}
	end

	if broad_search then
		local current_dir = vim.fn.expand("%:h")     -- Get the current buffer's directory
		local solutions, solution_filters, projs = M.find_sln_files(current_dir)

		return {
			solutions = solutions,
			solution_filters = solution_filters,
			projects = projs,
		}
	end

	local projects = csproj and { files = find_files_with_extension(csproj, ".csproj"), directory = csproj } or nil

	if not sln then
		return {
			solutions = nil,
			projects = projects,
		}
	end

	local slnf = targets.slnf_dir
	local slns = find_files_with_extension(sln, ".sln")
	local slnxs = find_files_with_extension(sln, ".slnx")

	return {
		solutions = vim.list_extend(slns, slnxs),
		solution_filters = slnf and find_files_with_extension(slnf, ".slnf"),
		projects = projects,
	}
end

---Tries to predict which target to use if we found some
---returning the potentially predicted target
---@param root RoslynNvimRootDir
---@return boolean multiple, string? predicted_target
function M.predict_target(root)
	if not root.solutions then
		return false, nil
	end

	local config_instance = config.get()
	local sln_api = require("roslyn.sln.api")

	local filtered_targets = vim.iter({ root.solutions, root.solution_filters })
			:flatten()
			:filter(function(target)
				if config_instance.ignore_target and config_instance.ignore_target(target) then
					return false
				end

				return not root.projects
						or vim.iter(root.projects.files):any(function(csproj_file)
							return sln_api.exists_in_target(target, csproj_file)
						end)
			end)
			:totable()

	if #filtered_targets > 1 then
		local chosen = config_instance.choose_target and config_instance.choose_target(filtered_targets)

		if chosen then
			return false, chosen
		end

		return true, nil
	else
		return false, filtered_targets[1]
	end
end

return M
