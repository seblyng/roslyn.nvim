local M = {}

M.notifications = {}
M.diagnostic_requests = {}

function M.server()
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
        elseif method == "textDocument/diagnostic" then
            table.insert(M.diagnostic_requests, { uri = params.textDocument.uri })
            handler(nil, { kind = "full", items = {} })
        elseif method == "sourceGeneratedDocument/_roslyn_getText" then
            handler(nil, { text = "namespace Generated {}", resultId = "1" })
        else
            assert(false, "Unhandled method: " .. method)
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
    M.notifications = {}
    M.diagnostic_requests = {}
end

return M
