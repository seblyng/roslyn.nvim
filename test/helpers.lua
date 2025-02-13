local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))
local os_sep = iswin and "\\" or "/"

local M = {}

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

return M
