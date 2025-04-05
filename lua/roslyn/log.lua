local M = {}

-- Define the path to the log file.
M.__log_file_path = vim.fn.stdpath("cache") .. "/roslyn.log"

-- Internal helper function to write a log entry.
local function write_log(log_line)
    -- Open the file in append mode (creates the file if it doesn't exist).
    vim.fn.mkdir(vim.fn.stdpath("cache"), "p")
    local file, err = io.open(M.__log_file_path, "a")
    if not file then
        error("Unable to open log file: " .. M.__log_file_path .. " (" .. tostring(err) .. ")")
    end

    file:write(log_line)
    file:close()
end

---@param msg string
function M.log(msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("%s %s\n", timestamp, msg)
    write_log(log_line)
end

return M
