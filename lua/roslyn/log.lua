local M = {}

local log_file = vim.fs.joinpath(vim.fn.stdpath("state"), "roslyn.log")
local file_handle = nil

---@param msg string
function M.log(msg)
    if not require("roslyn.config").get().debug then
        return
    end

    if not file_handle then
        vim.fn.mkdir(vim.fs.dirname(log_file), "p")
        file_handle = io.open(log_file, "a")
    end

    if file_handle then
        local ts = os.date("%Y-%m-%d %H:%M:%S")
        file_handle:write(string.format("[%s] %s\n", ts, msg))
        file_handle:flush()
    end
end

return M
