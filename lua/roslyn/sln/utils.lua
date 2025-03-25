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
        debug("\nRoslyn solution(s) found" .. vim.inspect(M.merge(slns, slnfs)) .. "\n")
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
  end

  search_upwards(current_dir)
  return slns, slnfs, csprojs
end

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
  local slns = {}    --- @type string[]
  local slnfs = {}   --- @type string[]

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

  local broad_search = config.get().broad_search
  if broad_search then
    local current_dir = vim.fn.expand("%:h")     -- Get the current buffer's directory
    local slns, sln_filters, csprojs = M.find_sln_files(current_dir)

    return {
      solutions = slns,
      solution_filters = sln_filters,
      projects = { files = csprojs, directory = targets.csproj_dir },
    }
  end

  local sln = targets.sln_dir
  local projects = {
    files = find_files_with_extensions(targets.csproj_dir, { ".csproj" }),
    directory = targets.csproj_dir,
  }

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

      if config_instance.broad_search then
        return true
      else
        return not root.projects
          or vim.iter(root.projects.files):any(function(csproj_file)
            return sln_api.exists_in_target(target, csproj_file)
          end)
      end
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
