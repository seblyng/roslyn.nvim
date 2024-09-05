---@type table<string, string>
local _pipe_names = {}

---@type vim.SystemObj?
local _current_server_object = nil

---@type vim.SystemObj[]
local _server_objects = {}

--- @param client vim.lsp.Client
--- @param config vim.lsp.ClientConfig
--- @return boolean
local function reuse_client_default(client, config)
    if client.name ~= config.name then
        return false
    end

    if config.root_dir then
        for _, dir in ipairs(client.workspace_folders or {}) do
            -- note: do not need to check client.root_dir since that should be client.workspace_folders[1]
            if config.root_dir == dir.name then
                return true
            end
        end
    end

    return false
end

local M = {}

---@param cmd string[]
---@param config vim.lsp.ClientConfig Configuration for the server.
---@param with_pipe_name fun(pipe_name: string): nil A function to execute after server start and pipe_name is known
function M.start_server(cmd, config, with_pipe_name)
    local all_clients = vim.lsp.get_clients()
    for _, client in pairs(all_clients) do
        if reuse_client_default(client, config) and _pipe_names[config.root_dir] then
            return with_pipe_name(_pipe_names[config.root_dir])
        end
    end

    _current_server_object = vim.system(cmd, {
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
            _pipe_names[config.root_dir] = pipe_name

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
        _pipe_names[config.root_dir] = nil
    end)
end

function M.stop_server(client_id)
    local client = vim.lsp.get_client_by_id(client_id)

    local server_object = _server_objects[client_id]
    if server_object then
        server_object:kill(9)
    end

    if client then
        _pipe_names[client.root_dir] = nil
    end
end

---@param client_id integer
function M.save_server_object(client_id)
    _server_objects[client_id] = _current_server_object
end

return M
