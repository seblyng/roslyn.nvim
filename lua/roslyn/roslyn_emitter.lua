local M = {
    events = {},
}

---@param event "stopped"
function M:on(event, callback)
    if not M.events[event] then
        M.events[event] = {}
    end
    table.insert(M.events[event], callback)
    return function()
        M:off(event, callback)
    end
end

---@param event "stopped"
function M:emit(event, ...)
    if M.events[event] then
        for _, callback in ipairs(M.events[event]) do
            callback(...)
        end
    end
end

function M:off(event, callback)
    if not M.events[event] then
        return
    end
    for i, cb in ipairs(M.events[event]) do
        if cb == callback then
            table.remove(M.events[event], i)
            break
        end
    end
end

return M
