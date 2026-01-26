local helpers = require("nvim-test.helpers")
local command = helpers.api.nvim_command
local system = helpers.fn.system

local M = helpers

local scratch_path = vim.uv.os_uname().sysname == "Darwin" and "/private/tmp/FooRoslynTest" or "/tmp/FooRoslynTest"
M.scratch = vim.fs.abspath(scratch_path)

---@param path string
---@param text? string
---@return string
function M.create_file(path, text)
    local dir = path:match("(.+)/[^/]+$")
    system({ "mkdir", "-p", vim.fs.joinpath(M.scratch, dir) })
    local f = assert(io.open(vim.fs.joinpath(M.scratch, path), "w"))
    f:write(text or "")
    f:close()
    return path
end

---@class RoslynTestHelperProjects
---@field name string
---@field path string

---@param path string
---@param projects RoslynTestHelperProjects[]
function M.create_sln_file(path, projects)
    local lines = {}

    local function append(line)
        table.insert(lines, line)
    end

    -- Header section
    append("Microsoft Visual Studio Solution File, Format Version 12.00")
    append("# Visual Studio Version 17")
    append("VisualStudioVersion = 17.0.31903.59")
    append("MinimumVisualStudioVersion = 10.0.40219.1")

    -- Create the Project entries.
    for _, proj in ipairs(projects) do
        -- Cycle through dummy GUIDs; for more projects they will repeat.
        append(
            'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = '
                .. string.format('"%s", "%s"', proj.name, proj.path)
                .. ', "{8B8A22ED-4262-4409-B9B1-36F334016FDB}"'
        )
        append("EndProject")
    end

    -- Global sections with configuration information.
    append("Global")
    append("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution")
    append("\t\tDebug|Any CPU = Debug|Any CPU")
    append("\t\tRelease|Any CPU = Release|Any CPU")
    append("\tEndGlobalSection")
    append("\tGlobalSection(SolutionProperties) = preSolution")
    append("\t\tHideSolutionNode = FALSE")
    append("\tEndGlobalSection")
    append("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution")

    -- For each project, define configurations.
    for _, _ in ipairs(projects) do
        append(string.format("\t\t{8B8A22ED-4262-4409-B9B1-36F334016FDB}.Debug|Any CPU.ActiveCfg = Debug|Any CPU"))
        append(string.format("\t\t{8B8A22ED-4262-4409-B9B1-36F334016FDB}.Debug|Any CPU.Build.0 = Debug|Any CPU"))
        append(string.format("\t\t{8B8A22ED-4262-4409-B9B1-36F334016FDB}.Release|Any CPU.ActiveCfg = Release|Any CPU"))
        append(string.format("\t\t{8B8A22ED-4262-4409-B9B1-36F334016FDB}.Release|Any CPU.Build.0 = Release|Any CPU"))
    end

    append("\tEndGlobalSection")
    append("EndGlobal")

    -- Combine all lines into one string.
    local sln_string = table.concat(lines, "\n")
    return M.create_file(path, sln_string)
end

function M.create_slnf_file(path, projects)
    local lines = {}

    local function append(line)
        table.insert(lines, line)
    end

    -- Header section
    append("{")
    append(string.format('  "path": %s,', path))
    append('  "projects": [')

    for _, proj in ipairs(projects) do
        append(string.format('    "%s"', proj.path))
    end

    append("  ]")
    append("}")
    --     ]

    -- Combine all lines into one string.
    local sln_string = table.concat(lines, "\n")
    return M.create_file(path, sln_string)
end

function M.create_slnx_file(path, projects)
    local lines = {}

    local function append(line)
        table.insert(lines, line)
    end

    -- Header section
    append("<Solution>")
    append("  <Configurations>")
    append('    <Platform Name="Any CPU" />')
    append('    <Platform Name="x64" />')
    append('    <Platform Name="x86" />')
    append("  </Configurations>")

    for _, proj in ipairs(projects) do
        append(string.format('  <Project Path="%s" />', proj.path))
    end

    append("</Solution>")

    -- Combine all lines into one string.
    local sln_string = table.concat(lines, "\n")
    return M.create_file(path, sln_string)
end

---@return string?
function M.predict_target(file_path, targets)
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))
    return helpers.exec_lua(function(targets0)
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").predict_target(bufnr, targets0)
    end, targets)
end

function M.api_projects(target)
    local sln = vim.fs.joinpath(M.scratch, target)
    return helpers.exec_lua(function(target0)
        return require("roslyn.sln.api").projects(target0)
    end, sln)
end

function M.setup(config)
    helpers.exec_lua(function(config0)
        if config0.ignore_target then
            local ignore = config0.ignore_target
            config0.ignore_target = function(sln)
                return string.match(sln, ignore) ~= nil
            end
        end

        if config0.choose_target then
            local choose = config0.choose_target
            config0.choose_target = function(target)
                return vim.iter(target):find(function(item)
                    if string.match(item, choose) then
                        return item
                    end
                end)
            end
        end

        require("roslyn.config").setup(config0)
    end, config)
end

---Sets up a one-shot choose_target that picks a solution once, then clears itself.
---@param pattern string Pattern to match against solution paths
function M.choose_solution_once(pattern)
    helpers.exec_lua(function(pattern0)
        local config = require("roslyn.config")
        local current = config.get()

        current.choose_target = function(targets)
            -- Clear ourselves after being called once
            current.choose_target = nil

            return vim.iter(targets):find(function(item)
                return string.match(item, pattern0)
            end)
        end
    end, pattern)
end

-- =============================================================================
-- Mock Server Helpers (for real LSP integration tests)
-- =============================================================================

---Configures the LSP to use the in-process test server.
function M.use_test_server()
    helpers.exec_lua(function()
        local cwd = vim.uv.cwd()
        local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))

        lsp_config.cmd = require("test.mock_server").server

        vim.lsp.config["roslyn"] = lsp_config
        vim.lsp.enable("roslyn")
    end)
end

---Gets notifications from the in-process test server.
---@return { method: string, params: table }[]
function M.get_mock_server_notifications()
    return helpers.exec_lua(function()
        return require("test.mock_server").notifications
    end)
end

---Opens a file and waits for LSP to attach to the current buffer.
---@param file_path string Path relative to scratch directory
---@param timeout? number Timeout in ms (default 5000)
---@return number bufnr
function M.open_file_and_wait_for_lsp(file_path, timeout)
    timeout = timeout or 5000
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))

    local attached = helpers.exec_lua(function(timeout0)
        local bufnr = vim.api.nvim_get_current_buf()
        return vim.wait(timeout0, function()
            -- Wait for a client to be attached to THIS buffer specifically
            local clients = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })
            if #clients == 0 then
                return false
            end
            -- Wait for client to be fully initialized
            for _, client in ipairs(clients) do
                if not client.initialized then
                    return false
                end
            end
            return true
        end, 50)
    end, timeout)

    assert(attached, "LSP client failed to attach within timeout")

    return helpers.api.nvim_get_current_buf()
end

---Gets info about all roslyn LSP clients.
---@param bufnr? number Buffer number
---@return { id: number, root_dir: string, attached_buffers: number[] }[]
function M.get_lsp_clients(bufnr)
    return helpers.exec_lua(function(bufnr0)
        local clients = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr0 })
        local result = {}
        for _, client in ipairs(clients) do
            local attached = vim.iter(pairs(client.attached_buffers))
                :map(function(buf)
                    return buf
                end)
                :totable()

            table.insert(result, {
                id = client.id,
                root_dir = client.root_dir,
                attached_buffers = attached,
            })
        end
        return result
    end, bufnr)
end

---Gets the selected solution from the global variable.
---@return string|nil
function M.get_selected_solution()
    return helpers.exec_lua(function()
        return vim.g.roslyn_nvim_selected_solution
    end)
end

---Waits until the specified number of roslyn LSP clients are running and initialized.
---@param count number Expected number of clients
---@param timeout? number Timeout in ms (default 5000)
---@return boolean success
function M.wait_for_client_count(count, timeout)
    timeout = timeout or 5000
    return helpers.exec_lua(function(count0, timeout0)
        return vim.wait(timeout0, function()
            local clients = vim.lsp.get_clients({ name = "roslyn" })
            if #clients ~= count0 then
                return false
            end
            for _, client in ipairs(clients) do
                if not client.initialized then
                    return false
                end
            end
            return true
        end, 50)
    end, count, timeout)
end

return M
