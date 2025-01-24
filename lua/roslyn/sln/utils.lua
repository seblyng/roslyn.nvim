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
	return dir:match("[Bb]in$") or dir:match("[Oo]bj$")
end

--- @param path string
--- @return string[] slns, string[] slnfs
local function find_solutions(path)
	local dirs = { path }
	local slns = {}    --- @type string[]
	local slnfs = {}   --- @type string[]

	while #dirs > 0 do
		local dir = table.remove(dirs, 1)

		for other, fs_obj_type in vim.fs.dir(dir) do
			local name = vim.fs.joinpath(dir, other)

			if fs_obj_type == "file" then
				if string.match(name, "%.sln$") or string.match(name, "%.slnx$") then
					slns[#slns + 1] = vim.fs.normalize(name)
				elseif string.match(name, "%.slnf$") then
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
		if not csproj_dir and string.match(name, "%.csproj$") then
			csproj_dir = path
		end

		if not slnf_dir and string.match(name, "%.slnf$") then
			slnf_dir = path
		end

		return string.match(name, "%.sln$") ~= nil or string.match(name, "%.slnx$")
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
		local slns = find_files_with_extension(sln, ".sln")
		local slnxs = find_files_with_extension(sln, ".slnx")

		return {
			solutions = vim.list_extend(slns, slnxs),
			solution_filters = slnf and find_files_with_extension(slnf, ".slnf"),
			projects = projects,
		}
	end
end

---Tries to predict which target to use if we found some
---returning the potentially predicted target
---@param root RoslynNvimRootDir
---@return boolean multiple, string? predicted_target
function M.predict_target(root)
	if not root.solutions then
		return false, nil
	end

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

-- Find solution alternative section
local debug_on = false
local function debug(...)
	if debug_on then
		vim.notify(...,vim.log.levels.DEBUG)
	end
end

local excluded_dirs = {
	node_modules = "node_modules",
	git = ".git",
	dist = "dist",
	wwwroot = "wwwroot",
	properties = "[Pp]roperties",
	build = "build",
	bin = "bin",
	debug = "debug",
	obj = "obj",
}

local function excluded(name)
	for _, pattern in pairs(excluded_dirs) do
		if string.match(name:lower(), pattern) then
			return true
		end
	end
	return false
end

local patterns = {
	sln = "%.sln$",       -- % is excape char
	sln_ = "%.sln%a?$",   -- %a is letter
	csproj = "%.csproj$",
}

local function is_proj_or_sln(name)
	for _, pattern in pairs(patterns) do
		if string.match(name:lower(), pattern) then
			return true
		end
	end
	return false
end

local function is_sln(name)
	return string.match(name, patterns.sln) ~= nil
end

local function starts_with_symbol(name)
	return string.match(name, "^[^0-9A-Za-z_]") ~= nil
end

local function merge(table1, table2)
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

local function set_solution(path)
	if not path then
		path = path and path or "nil"
		vim.notify("Incorrect sln/proj file" .. path, vim.log.levels.WARN)
		return
	end

	-- Store the selected path
	vim.g.roslyn_nvim_selected_solution = path

	-- Notify user
	debug("Selected: " .. path, vim.log.levels.INFO)

	-- Start lsp
	local roslyn_lsp = require("roslyn.lsp")
	local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
	roslyn_lsp.start(vim.api.nvim_get_current_buf(), sln_dir, roslyn_lsp.on_init_sln)
end

---Show the list of sln/proj filse to select from ui
---@param files table
local function handle_matches(files)
	if #files == 0 then
		vim.notify("No solution or project files found", vim.log.levels.WARN)
		return
	end

	-- Sort solutions first
	local slns = {}
	local csprojs = {}
	for _, file in ipairs(files) do
		if string.match(file:lower(), patterns.sln_) ~= nil then
			table.insert(slns, file)
		else
			table.insert(csprojs, file)
		end
	end
	files = merge(slns, csprojs)

	if #slns == 1 then
		set_solution(slns[1])
		return
	end

	vim.notify("Multiple solution or project files found", vim.log.levels.INFO)
	-- Show selection UI
	vim.ui.select(files, {
		prompt = "Select Solution/Project File",
	}, function(choice)
		if not choice then
			return
		end
		set_solution(choice)
	end)
end

local function find_sln_files(current_dir)
	local visited_dirs = {}
	local non_scaned_dirs = {}

	---finds proj or sln files in the directory
	---@param dir string
	---@return table
	local function find_in_dir(dir)
		local files = {}
		visited_dirs["find_in_dir " .. dir] = true
		debug("find_in_dir " .. dir)
		local handle, err = vim.uv.fs_scandir(dir)

		if not handle then
			vim.notify("Error scanning in directory: " .. err, vim.log.levels.WARN)
			return files
		end

		while true do
			local name, type = vim.uv.fs_scandir_next(handle)
			if not name then
				debug("find_in_dir no more files " .. dir)
				break
			end

			local full_path = vim.fs.normalize(vim.fs.joinpath(dir, name))

			if not visited_dirs[full_path] and not excluded(name) and not starts_with_symbol(name) then
				if type == "file" and is_proj_or_sln(name) then
					debug("find_in_dir ---  proj --- " .. full_path)
					table.insert(files, full_path)
				elseif type == "directory" then
					table.insert(non_scaned_dirs, full_path)
				end
			end
			visited_dirs[full_path] = true
			debug("find_in_dir fullpath " .. full_path)
		end
		return files
	end

	local function search_upwards(path)
		local files = {}
		local dir = path
		while true do
			if not excluded(dir) then
				local newfiles = find_in_dir(dir)
				if #newfiles > 0 then
					files = merge(files, newfiles)
					for _, file in ipairs(newfiles) do
						if is_sln(file) then
							debug("solution found " .. dir)
							return files
						end
					end
				end
			end

			if #non_scaned_dirs > 0 then
				dir = table.remove(non_scaned_dirs, 1)
				debug("non_scaned_dirs entry used" .. dir)
			else
				local one_up_folder = vim.uv.fs_realpath(path .. "/..")         -- Move to parent directory
				if one_up_folder == path then
					break
				end
				path = one_up_folder
				dir = one_up_folder
			end
		end
		debug(vim.inspect(visited_dirs))
		return files
	end

	return search_upwards(current_dir)
end

-- Main function
function M.select_solution()
	debug_on = false
	local co = coroutine.create(function()
		local current_dir = vim.fn.expand("%:h")     -- Get the current buffer's directory
		vim.notify("Searching for solution files [" .. current_dir .. "]", vim.log.levels.INFO)

		local files = find_sln_files(current_dir)
		debug("found solutions: " .. vim.inspect(files), vim.log.levels.INFO)

		handle_matches(files)
	end)
	coroutine.resume(co)
end

return M
