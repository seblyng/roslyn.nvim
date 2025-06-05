local log = require("roslyn.log")
local sln_api = require("roslyn.sln.api")

local M = {}

--- Searches for files with a specific extension within a directory.
--- Only files matching the provided extension are returned.
---
--- @param dir string The directory path for the search.
--- @param extensions string[] The file extensions to look for (e.g., ".sln").
---
--- @return string[] List of file paths that match the specified extension.
function M.find_files_with_extensions(dir, extensions)
    local matches = {}

    log.log(string.format("find_files_with_extensions dir: %s, extensions: %s", dir, vim.inspect(extensions)))

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

---@param targets string[]
---@param csproj string
---@return string[]
local function filter_targets(targets, csproj)
    local config = require("roslyn.config").get()
    return vim.iter(targets)
        :filter(function(target)
            if config.ignore_target and config.ignore_target(target) then
                return false
            end

            return not csproj or sln_api.exists_in_target(target, csproj)
        end)
        :totable()
end

---@param buffer number
local function resolve_broad_search_root(buffer)
    local sln_root = vim.fs.root(buffer, function(fname, _)
        return fname:match("%.sln$") ~= nil or fname:match("%.slnx$") ~= nil
    end)

    local git_root = vim.fs.root(buffer, ".git")
    if sln_root and git_root then
        return git_root and sln_root:find(git_root, 1, true) and git_root or sln_root
    else
        return sln_root or git_root
    end
end

function M.find_solutions(bufnr)
    local results = vim.fs.find(function(name)
        return name:match("%.sln$") or name:match("%.slnx$") or name:match("%.slnf$")
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr), limit = math.huge })
    log.log(string.format("find_solutions found: %s", vim.inspect(results)))
    return results
end

-- Dirs we are not looking for solutions inside
local ignored_dirs = {
    "obj",
    "bin",
    ".git",
}

function M.find_solutions_broad(bufnr)
    local root = resolve_broad_search_root(bufnr)
    local dirs = { root }
    local slns = {} --- @type string[]

    while #dirs > 0 do
        local dir = table.remove(dirs, 1)

        for other, fs_obj_type in vim.fs.dir(dir) do
            local name = vim.fs.joinpath(dir, other)

            if fs_obj_type == "file" then
                if name:match("%.sln$") or name:match("%.slnx$") or name:match("%.slnf$") then
                    slns[#slns + 1] = vim.fs.normalize(name)
                end
            elseif fs_obj_type == "directory" and not vim.list_contains(ignored_dirs, vim.fs.basename(name)) then
                dirs[#dirs + 1] = name
            end
        end
    end

    log.log(string.format("find_solutions_broad root: %s, found: %s", root, vim.inspect(slns)))
    return slns
end

---@param bufnr number
---@param solutions string[]
---@param preselected_sln string?
function M.root_dir(bufnr, solutions, preselected_sln)
    log.log(string.format("root_dir solutions: %s, preselected_sln: %s", vim.inspect(solutions), preselected_sln))
    if #solutions == 1 then
        local result = vim.fs.dirname(solutions[1])
        log.log(string.format("root_dir single solution result: %s", result))
        return result
    end

    local csproj = vim.fs.find(function(name)
        return name:match("%.csproj$") ~= nil
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr) })[1]

    local filtered_targets = filter_targets(solutions, csproj)
    if #filtered_targets > 1 then
        local config = require("roslyn.config").get()
        local chosen = config.choose_target and config.choose_target(filtered_targets)
        if chosen then
            local result = vim.fs.dirname(chosen)
            log.log(string.format("root_dir chosen result: %s", result))
            return result
        else
            if preselected_sln and vim.list_contains(filtered_targets, preselected_sln) then
                local result = vim.fs.dirname(preselected_sln)
                log.log(string.format("root_dir preselected result: %s", result))
                return result
            end

            log.log("root_dir: Multiple potential target files found. Use :Roslyn target to select a target.")
            vim.notify(
                "Multiple potential target files found. Use `:Roslyn target` to select a target.",
                vim.log.levels.INFO,
                { title = "roslyn.nvim" }
            )
            return nil
        end
    else
        local selected_solution = vim.g.roslyn_nvim_selected_solution
        local result = vim.fs.dirname(filtered_targets[1])
            or selected_solution and vim.fs.dirname(selected_solution)
            or csproj and vim.fs.dirname(csproj)
        log.log(
            string.format(
                "root_dir fallback result: %s, selected solution: %s, csproj: %s",
                result,
                selected_solution,
                csproj
            )
        )
        return result
    end
end

---@param bufnr number
---@param targets string[]
---@return string?
function M.predict_target(bufnr, targets)
    local config = require("roslyn.config").get()

    local csproj = vim.fs.find(function(name)
        return name:match("%.csproj$") ~= nil
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr) })[1]

    local filtered_targets = filter_targets(targets, csproj)
    local result
    if #filtered_targets > 1 then
        result = config.choose_target and config.choose_target(filtered_targets) or nil
    else
        result = filtered_targets[1]
    end
    log.log(string.format("predict_target targets: %s, result: %s", vim.inspect(targets), result))
    return result
end

return M
