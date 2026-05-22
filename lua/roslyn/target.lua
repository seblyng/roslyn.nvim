local sln_api = require("roslyn.sln.api")
local store = require("roslyn.store")

local M = {}

local pending_by_root = {}

---@param targets string[]
---@param csproj? string
---@return string[]
local function filter_targets(targets, csproj)
    local config = require("roslyn.config").get()
    local filtered = {}

    for _, target in ipairs(targets) do
        if
            not (config.ignore_target and config.ignore_target(target))
            and (not csproj or sln_api.exists_in_target(target, csproj))
        then
            filtered[#filtered + 1] = target
        end
    end

    return filtered
end

---@param bufnr number
---@param targets string[]
---@return string?
function M.predict_target(bufnr, targets)
    local config = require("roslyn.config").get()

    local csproj = require("roslyn.sln.discovery").find_project(bufnr)
    local filtered_targets = filter_targets(targets, csproj)
    if #filtered_targets > 1 then
        return config.choose_target and config.choose_target(filtered_targets) or nil
    end

    return filtered_targets[1]
end

---@param bufnr number
---@return { kind: "root", root_dir: string } | { kind: "ambiguous", targets: string[] } | { kind: "none" }
local function resolve_root(bufnr)
    local config = require("roslyn.config").get()
    local discovery = require("roslyn.sln.discovery")
    local solutions = discovery.find_solutions_for_buffer(bufnr)

    if #solutions == 1 then
        return { kind = "root", root_dir = vim.fs.dirname(solutions[1]) }
    end

    local csproj = discovery.find_project(bufnr)

    local filtered_targets = filter_targets(solutions, csproj)
    if #filtered_targets > 1 then
        local chosen = config.choose_target and config.choose_target(filtered_targets)
        if chosen then
            return { kind = "root", root_dir = vim.fs.dirname(chosen) }
        end

        local possible_solutions = vim.iter(vim.lsp.get_clients({ name = "roslyn" }))
            :map(function(client)
                local target = store.get(client.id)
                return target and vim.list_contains(filtered_targets, target) and target or nil
            end)
            :totable()

        if #possible_solutions == 1 then
            return { kind = "root", root_dir = vim.fs.dirname(possible_solutions[1]) }
        end

        return { kind = "ambiguous", targets = filtered_targets }
    end

    if #filtered_targets == 1 then
        return { kind = "root", root_dir = vim.fs.dirname(filtered_targets[1]) }
    end

    local selected_solution = store.get_selected_target()
    if selected_solution then
        return { kind = "root", root_dir = vim.fs.dirname(selected_solution) }
    end

    if csproj then
        return { kind = "root", root_dir = vim.fs.dirname(csproj) }
    end

    return { kind = "none" }
end

---@param bufnr number
---@param root_dir string
---@return table
local function resolve_open_target(bufnr, root_dir)
    local discovery = require("roslyn.sln.discovery")
    local selected_solution = store.get_selected_target()
    local solutions, projects = discovery.find_target_files(root_dir)

    local solution = M.predict_target(bufnr, solutions)
    if solution then
        return { kind = "solution", root_dir = root_dir, target = solution }
    end

    if #projects > 0 then
        return { kind = "project", root_dir = root_dir, projects = projects }
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

    local existing_client = vim.api.nvim_buf_get_name(bufnr):match("^roslyn%-source%-generated://")
        and vim.lsp.get_clients({ name = "roslyn" })[1]
    if existing_client and existing_client.config.root_dir then
        return { kind = "reuse", root_dir = existing_client.config.root_dir }
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
    if not decision.root_dir or (decision.kind ~= "solution" and decision.kind ~= "project") then
        return
    end

    pending_by_root[decision.root_dir] = decision
end

---@param root_dir string
---@return table?
function M.consume(root_dir)
    local decision = pending_by_root[root_dir]
    pending_by_root[root_dir] = nil
    return decision
end

return M
