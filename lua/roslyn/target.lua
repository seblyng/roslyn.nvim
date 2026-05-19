local log = require("roslyn.log")
local sln_api = require("roslyn.sln.api")
local store = require("roslyn.store")

local M = {}

local pending_by_root = {}

---@param bufnr number
---@return string?
local function find_csproj_file(bufnr)
    return vim.fs.find(function(name)
        return name:match("%.csproj$") ~= nil
    end, { upward = true, path = vim.api.nvim_buf_get_name(bufnr) })[1]
end

---@param targets string[]
---@param csproj? string
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

---@param bufnr number
---@return { kind: "root", root_dir: string } | { kind: "ambiguous", targets: string[] } | { kind: "none" }
local function resolve_root(bufnr)
    local config = require("roslyn.config").get()
    local solutions = require("roslyn.sln.discovery").find_solutions_for_buffer(bufnr)

    if #solutions == 1 then
        return { kind = "root", root_dir = vim.fs.dirname(solutions[1]) }
    end

    local csproj = find_csproj_file(bufnr)

    local filtered_targets = filter_targets(solutions, csproj)
    if #filtered_targets > 1 then
        local chosen = config.choose_target and config.choose_target(filtered_targets)
        if chosen then
            return { kind = "root", root_dir = vim.fs.dirname(chosen) }
        end

        local possible_solutions = vim.iter(vim.lsp.get_clients({ name = "roslyn" }))
            :map(function(client)
                local client_solution = store.get_client_target(client.id)
                if client_solution and vim.list_contains(filtered_targets, client_solution) then
                    return vim.fs.dirname(client_solution)
                end
            end)
            :totable()

        if #possible_solutions == 1 and possible_solutions[1] then
            return { kind = "root", root_dir = possible_solutions[1] }
        end

        return { kind = "ambiguous", targets = filtered_targets }
    end

    local selected_solution = store.get_selected_target()
    local root_dir = vim.fs.dirname(filtered_targets[1])
        or selected_solution and vim.fs.dirname(selected_solution)
        or csproj and vim.fs.dirname(csproj)

    if root_dir then
        return { kind = "root", root_dir = root_dir }
    end

    return { kind = "none" }
end

---@param bufnr number
---@param root_dir string
---@return table
local function resolve_open_target(bufnr, root_dir)
    local discovery = require("roslyn.sln.discovery")
    local selected_solution = store.get_selected_target()

    local files = discovery.find_files_with_extensions(root_dir, { ".sln", ".slnx", ".slnf" })

    local solution = M.predict_target(bufnr, files)
    if solution then
        return { kind = "solution", root_dir = root_dir, target = solution }
    end

    local csproj = discovery.find_files_with_extensions(root_dir, { ".csproj" })
    if #csproj > 0 then
        return { kind = "project", root_dir = root_dir, projects = csproj }
    end

    if selected_solution then
        return { kind = "solution", root_dir = root_dir, target = selected_solution }
    end

    return { kind = "none", root_dir = root_dir }
end

---@param bufnr number
---@return table
function M.resolve(bufnr)
    local config = require("roslyn.config").get()
    local selected_solution = store.get_selected_target()
    if config.lock_target and selected_solution then
        return { kind = "solution", root_dir = vim.fs.dirname(selected_solution), target = selected_solution }
    end

    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name:match("^roslyn%-source%-generated://") then
        local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
        if existing_client and existing_client.config.root_dir then
            return { kind = "reuse", root_dir = existing_client.config.root_dir }
        end
    end

    local root = resolve_root(bufnr)
    if root.kind ~= "root" then
        return root
    end

    return resolve_open_target(bufnr, root.root_dir)
end

---@param decision table
function M.notify_if_needed(decision)
    if decision.kind ~= "ambiguous" then
        return
    end

    vim.notify(
        "Multiple potential target files found. Use `:Roslyn target` to select a target.",
        vim.log.levels.INFO,
        { title = "roslyn.nvim" }
    )
end

---@param decision table
function M.remember(decision)
    if decision.root_dir and (decision.kind == "solution" or decision.kind == "project") then
        pending_by_root[decision.root_dir] = decision
    end
end

---@param root_dir string
---@return table?
function M.consume(root_dir)
    local decision = pending_by_root[root_dir]
    pending_by_root[root_dir] = nil
    return decision
end

return M
