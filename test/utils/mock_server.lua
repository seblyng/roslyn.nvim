local M = {}

M.notifications = {}
M.requests = {}
M.responses = {}

--- Returned by a response function to make the server refuse the request
M.refuse = {}

local default_responses = {
    ["textDocument/diagnostic"] = function()
        return { kind = "full", items = {} }
    end,
    ["workspace/textDocumentContent"] = function()
        return { text = "namespace Generated {}" }
    end,
    ["textDocument/documentSymbol"] = function()
        return {}
    end,
    ["textDocument/runTests"] = function()
        return {}
    end,
}

---@type vim.lsp.rpc.Dispatchers?
local client_dispatchers

--- Sends a notification to the client, e.g. `$/progress`
---@param method string
---@param params table
function M.notify_client(method, params)
    assert(client_dispatchers, "mock server is not running")
    client_dispatchers.notification(method, params)
end

--- Sends a request to the client. Runs the client's handler inside a coroutine like `vim.lsp.rpc` does,
--- so handlers may yield before they respond.
---@param method string
---@param params table
---@param on_response? fun(result: any, err: lsp.ResponseError?)
function M.request_client(method, params, on_response)
    assert(client_dispatchers, "mock server is not running")
    coroutine.wrap(function()
        local result, err = client_dispatchers.server_request(method, params)
        if on_response then
            on_response(result, err)
        end
    end)()
end

---@param dispatchers vim.lsp.rpc.Dispatchers
function M.server(dispatchers)
    client_dispatchers = dispatchers
    local closing = false
    local srv = {}

    function srv.request(method, params, handler)
        if method == "initialize" then
            handler(nil, {
                capabilities = {
                    diagnosticProvider = {
                        interFileDependencies = true,
                        workspaceDiagnostics = false,
                    },
                },
            })
        elseif method == "shutdown" then
            handler(nil, nil)
        else
            local respond = M.responses[method] or default_responses[method]
            assert(respond, "Unhandled method: " .. method)
            M.requests[method] = M.requests[method] or {}
            table.insert(M.requests[method], params)
            local result = respond(params)
            if result == M.refuse then
                return false
            end
            handler(nil, result)
            return true
        end
    end

    function srv.notify(method, params)
        if method == "exit" then
            closing = true
        elseif method == "solution/open" or method == "project/open" then
            table.insert(M.notifications, { method = method, params = params })
        end
    end

    function srv.is_closing()
        return closing
    end

    function srv.terminate()
        closing = true
    end

    return srv
end

function M.reset()
    client_dispatchers = nil
    M.notifications = {}
    M.requests = {}
    M.responses = {}
end

return M
