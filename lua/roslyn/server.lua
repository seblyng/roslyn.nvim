---@type table<string, string>
local _pipe_names = {}

---@type boolean
local start_pending = false

---@type vim.SystemObj?
local _current_server_object = nil

---@type vim.SystemObj[]
local _server_objects = {}

--- @param client vim.lsp.Client
--- @param config vim.lsp.ClientConfig
--- @return boolean
local function reuse_client_default(client, config)
    return vim.iter(client.workspace_folders or {}):any(function(it)
        return config.root_dir == it.name
    end)
end

local M = {}

---@param bufnr integer
---@param config vim.lsp.ClientConfig Configuration for the server.
---@param pipe_name string
local function with_pipe_name(bufnr, config, pipe_name)
    config.cmd = vim.lsp.rpc.connect(pipe_name)
    local client_id = vim.lsp.start(config, {
        bufnr = bufnr,
    })
    if client_id then
        _server_objects[client_id] = _current_server_object
    end
    vim.defer_fn(function()
        --NOTE: Give the server some time to init
        start_pending = false
    end, 1000)
end

---@param bufnr integer
---@param cmd string[]
---@param config vim.lsp.ClientConfig Configuration for the server.
function M.start_server(bufnr, cmd, config)
    if start_pending then
        --NOTE: Wait for the previous server to start (rzls spawns lots of roslyns)
        vim.defer_fn(function()
            M.start_server(bufnr, cmd, config)
        end, 250)
        return
    end
    start_pending = true
    local all_clients = vim.lsp.get_clients({ name = "roslyn" })
    for _, client in pairs(all_clients) do
        if reuse_client_default(client, config) and _pipe_names[config.root_dir] then
            return with_pipe_name(bufnr, config, _pipe_names[config.root_dir])
        end
    end

    _current_server_object = vim.system(cmd, {
        detach = not vim.uv.os_uname().version:find("Windows"),
        stdout = function(_, data)
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
                with_pipe_name(bufnr, config, pipe_name)
            end)
        end,
        stderr = function(_, chunk)
            if chunk then
                vim.lsp.log.error("rpc", "dotnet", "stderr", chunk)
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

function M.get_pipes()
    ---NOTE: This is used by rzls.nvim for init
    return _pipe_names
end

return M
