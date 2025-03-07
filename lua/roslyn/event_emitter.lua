local M = {}

function M:new()
    local obj = {
        _events = {},
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function M:on(event, callback)
    if not self._events[event] then
        self._events[event] = {}
    end
    table.insert(self._events[event], callback)
end

function M:emit(event, ...)
    if self._events[event] then
        for _, callback in ipairs(self._events[event]) do
            callback(...)
        end
    end
end

function M:off(event, callback)
    if not self._events[event] then
        return
    end
    for i, cb in ipairs(self._events[event]) do
        if cb == callback then
            table.remove(self._events[event], i)
            break
        end
    end
end

function M:clear(event)
    self._events[event] = nil
end

return M
