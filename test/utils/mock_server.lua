local M = {}

M.notifications = {}

function M.server()
    local closing = false
    local srv = {}

    function srv.request(method, _, handler)
        if method == "initialize" then
            handler(nil, { capabilities = {} })
        elseif method == "shutdown" then
            handler(nil, nil)
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
end

return M
