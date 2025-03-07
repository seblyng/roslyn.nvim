local EventEmitter = require "roslyn.event_emitter"
local RoslynEmitter = EventEmitter:new()

function RoslynEmitter:on_stopped(callback)
    self:on("stopped", callback)
end

function RoslynEmitter:on_started(callback)
    self:on("started", callback)
end

function RoslynEmitter:emit_stopped(...)
    self:emit("stopped", ...)
end

function RoslynEmitter:emit_started(...)
    self:emit("started", ...)
end

return RoslynEmitter
