---@type string?
local _pipe_name = nil
---@type vim.SystemObj?
local _server_object = nil

local M = {}

---@param cmd string[]
---@param with_pipe_name fun(pipe_name: string): nil A function to execute after server start and pipe_name is known
function M.start_server(cmd, with_pipe_name)
    if _pipe_name then
        with_pipe_name(_pipe_name)
        return
    end
    if _server_object then
        return
    end
    _server_object = vim.system(cmd, {
        detach = not vim.uv.os_uname().version:find("Windows"),
        stdout = function(_, data)
            if not data then
                return
            end

            -- try parse data as json
            local success, json_obj = pcall(vim.json.decode, data)
            if not success then
                return
            end

            local pipe_name = json_obj["pipeName"]
            if not pipe_name then
                return
            end

            -- Cache the pipe name so we only start roslyn once.
            _pipe_name = pipe_name

            vim.schedule(function()
                with_pipe_name(pipe_name)
            end)
        end,
        stderr_handler = function(_, chunk)
            local log = require("vim.lsp.log")
            if chunk and log.error() then
                log.error("rpc", "dotnet", "stderr", chunk)
            end
        end,
    }, function()
        _pipe_name = nil
    end)
end

function M.stop_server()
    if _server_object then
        _server_object:kill(9)
    end
    _pipe_name = nil
    _server_object = nil
end

return M
