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
---@param csproj_files string[]
---@return string[]
local function filter_targets(targets, csproj_files)
    local config = require("roslyn.config").get()
    return vim.iter(targets)
        :filter(function(target)
            if config.ignore_target and config.ignore_target(target) then
                return false
            end

            return vim.iter(csproj_files):any(function(csproj_path)
                return sln_api.exists_in_target(target, csproj_path)
            end)
        end)
        :totable()
end

---@param paths string[]
---@return string?
local function get_shortest_path(paths)
    local shortest = nil
    for _, path in ipairs(paths) do
        local dir = vim.fs.dirname(path)
        if not shortest or #dir < #shortest then
            shortest = dir
        end
    end
    return shortest
end

---@param buffer number
---@return string?
local function resolve_broad_search_root(buffer)
    local solutions = M.find_solutions(buffer)
    local sln_root = get_shortest_path(solutions)

    local git_root = vim.fs.root(buffer, ".git")
    if sln_root and git_root then
        return git_root and sln_root:find(git_root, 1, true) and git_root or sln_root
    else
        return sln_root or git_root
    end
end

---@param bufnr number
---@return string[]
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

---@param bufnr number
---@return string[]
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
---@return string[]
local function find_csproj_file(bufnr)
    return vim.fs.find(function(name)
        return name:match("%.csproj$") ~= nil
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr), limit = math.huge })
end

---@param bufnr number
---@return string?
function M.root_dir(bufnr)
    local config = require("roslyn.config").get()
    local solutions = config.broad_search and M.find_solutions_broad(bufnr) or M.find_solutions(bufnr)

    if #solutions == 1 then
        return vim.fs.dirname(solutions[1])
    end

    local csproj_files = find_csproj_file(bufnr)

    local filtered_targets = filter_targets(solutions, csproj_files)
    if #filtered_targets > 1 then
        local chosen = config.choose_target and config.choose_target(filtered_targets)
        if chosen then
            return vim.fs.dirname(chosen)
        end

        -- Try to find an existing client attached to one of the filtered solutions
        -- If we find one, then assume that they want to reuse that one
        -- If we find multiple or none, then we cannot decide which one to use
        local possible_solutions = vim.iter(vim.lsp.get_clients({ name = "roslyn" }))
            :map(function(client)
                local client_solution = require("roslyn.store").get(client.id)
                if client_solution and vim.list_contains(filtered_targets, client_solution) then
                    return vim.fs.dirname(client_solution)
                end
            end)
            :totable()

        if #possible_solutions == 1 and possible_solutions[1] then
            return possible_solutions[1]
        end

        vim.notify(
            "Multiple potential target files found. Use `:Roslyn target` to select a target.",
            vim.log.levels.INFO,
            { title = "roslyn.nvim" }
        )
        return nil
    end

    local selected_solution = vim.g.roslyn_nvim_selected_solution
    return vim.fs.dirname(filtered_targets[1])
        or selected_solution and vim.fs.dirname(selected_solution)
        or csproj_files[1] and vim.fs.dirname(csproj_files[1])
end

---@param bufnr number
---@param targets string[]
---@return string?
function M.predict_target(bufnr, targets)
    local config = require("roslyn.config").get()

    local csproj = find_csproj_file(bufnr)
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
