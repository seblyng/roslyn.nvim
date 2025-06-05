local M = {}

function M.log(msg)
    if not require("roslyn.config").get().debug then
        return
    end

    local log_file = vim.fs.joinpath(vim.fn.stdpath("state"), "roslyn.log")
    vim.fn.mkdir(vim.fs.dirname(log_file), "p")

    local f = io.open(log_file, "a")
    if f then
        local ts = os.date("%Y-%m-%d %H:%M:%S")
        f:write(string.format("[%s] %s\n", ts, msg))
        f:close()
    end
end

return M
