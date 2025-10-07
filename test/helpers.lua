local helpers = require("nvim-test.helpers")
local command = helpers.api.nvim_command
local system = helpers.fn.system

local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))
local os_sep = iswin and "\\" or "/"

local M = helpers

local function split_windows_path(path)
    local prefix = ""

    --- Match pattern. If there is a match, move the matched pattern from the path to the prefix.
    --- Returns the matched pattern.
    ---
    --- @param pattern string Pattern to match.
    --- @return string|nil Matched pattern
    local function match_to_prefix(pattern)
        local match = path:match(pattern)

        if match then
            prefix = prefix .. match --[[ @as string ]]
            path = path:sub(#match + 1)
        end

        return match
    end

    local function process_unc_path()
        return match_to_prefix("[^/]+/+[^/]+/+")
    end

    if match_to_prefix("^//[?.]/") then
        -- Device paths
        local device = match_to_prefix("[^/]+/+")

        -- Return early if device pattern doesn't match, or if device is UNC and it's not a valid path
        if not device or (device:match("^UNC/+$") and not process_unc_path()) then
            return prefix, path, false
        end
    elseif match_to_prefix("^//") then
        -- Process UNC path, return early if it's invalid
        if not process_unc_path() then
            return prefix, path, false
        end
    elseif path:match("^%w:") then
        -- Drive paths
        prefix, path = path:sub(1, 2), path:sub(3)
    end

    -- If there are slashes at the end of the prefix, move them to the start of the body. This is to
    -- ensure that the body is treated as an absolute path. For paths like C:foo/bar, there are no
    -- slashes at the end of the prefix, so it will be treated as a relative path, as it should be.
    local trailing_slash = prefix:match("/+$")

    if trailing_slash then
        prefix = prefix:sub(1, -1 - #trailing_slash)
        path = trailing_slash .. path --[[ @as string ]]
    end

    return prefix, path, true
end

local function expand_home(path, sep)
    sep = sep or os_sep

    if vim.startswith(path, "~") then
        local home = vim.uv.os_homedir() or "~" --- @type string

        if home:sub(-1) == sep then
            home = home:sub(1, -2)
        end

        path = home .. path:sub(2)
    end

    return path
end

-- NOTE: Copy this from neovim as it isn't available in stable at the time of writing
function M.abspath(path)
    -- Expand ~ to user's home directory
    path = expand_home(path)

    -- Convert path separator to `/`
    path = path:gsub(os_sep, "/")

    local prefix = ""

    if iswin then
        prefix, path = split_windows_path(path)
    end

    if vim.startswith(path, "/") then
        -- Path is already absolute, do nothing
        return prefix .. path
    end

    -- Windows allows paths like C:foo/bar, these paths are relative to the current working directory
    -- of the drive specified in the path
    local cwd = (iswin and prefix:match("^%w:$")) and vim.uv.fs_realpath(prefix) or vim.uv.cwd()
    assert(cwd ~= nil)
    -- Convert cwd path separator to `/`
    cwd = cwd:gsub(os_sep, "/")

    -- Prefix is not needed for expanding relative paths, as `cwd` already contains it.
    return vim.fs.joinpath(cwd, path)
end

local scratch_path = vim.uv.os_uname().sysname == "Darwin" and "/private/tmp/FooRoslynTest" or "/tmp/FooRoslynTest"
M.scratch = M.abspath(scratch_path)

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
            string.format(
                'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "%s", "%s", "{8B8A22ED-4262-4409-B9B1-36F334016FDB}"',
                proj.name,
                proj.path
            )
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

function M.get_root_dir(file_path, preselected)
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))

    return helpers.exec_lua(function(path, preselected0)
        package.path = path
        vim.g.roslyn_nvim_selected_solution = preselected0
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").root_dir(bufnr)
    end, package.path, preselected)
end

function M.find_solutions(file_path)
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))
    return helpers.exec_lua(function(path)
        package.path = path
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").find_solutions(bufnr)
    end, package.path)
end

function M.find_solutions_broad(file_path)
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))
    return helpers.exec_lua(function(path)
        package.path = path
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").find_solutions_broad(bufnr)
    end, package.path)
end

---@return string?
function M.predict_target(file_path, targets)
    command("edit " .. vim.fs.joinpath(M.scratch, file_path))
    return helpers.exec_lua(function(path, targets0)
        package.path = path
        local bufnr = vim.api.nvim_get_current_buf()
        return require("roslyn.sln.utils").predict_target(bufnr, targets0)
    end, package.path, targets)
end

function M.api_projects(target)
    local sln = vim.fs.joinpath(M.scratch, target)
    return helpers.exec_lua(function(path, target0)
        package.path = path
        return require("roslyn.sln.api").projects(target0)
    end, package.path, sln)
end

function M.setup(config)
    helpers.exec_lua(function(path, config0)
        package.path = path
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
    end, package.path, config)
end

return M
