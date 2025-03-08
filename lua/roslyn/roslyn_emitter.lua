local M = {
    events = {},
}

local function on(event, callback)
    if not M.events[event] then
        M.events[event] = {}
    end
    table.insert(M.events[event], callback)
    return function()
        M:off(event, callback)
    end
end

local function emit(event, ...)
    if M.events[event] then
        for _, callback in ipairs(M.events[event]) do
            callback(...)
        end
    end
end

local function off(event, callback)
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

---@param callback fun(remove_listener: fun()) # Callback function that is invoked when the Roslyn server is stopped. Accepts a function parameter for removing the event listener.
---@return fun() # Returns a cleanup function for removing the listener manually.
---```lua
--- local remove_listener = M:on_stopped(function(remove_listener2)
---     --For oneshot jobs
---     remove_listener2()
--- end)
---
--- remove_listener()
---```
function M:on_stopped(callback)
    local wrapped
    wrapped = function()
        callback(function()
            off("stopped", wrapped)
        end)
    end

    on("stopped", wrapped)
    return function()
        off("stopped", wrapped)
    end
end

--- Emits a stop event notifying all the M:on_stopped subscribers
function M:emit_stopped(...)
    emit("stopped", ...)
end

return M
