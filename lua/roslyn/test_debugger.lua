local M = {}

local attach_timeout_ms = 30000
local adapter = "coreclr"

---@param process_id integer
---@return boolean attached
function M.attach(process_id)
    local request_coroutine, is_main = coroutine.running()
    assert(not is_main, "attaching the debugger must run inside a coroutine")

    local has_dap, dap = pcall(require, "dap")
    if not has_dap then
        vim.notify("Debugging tests requires nvim-dap", vim.log.levels.ERROR, { title = "roslyn.nvim" })
        return false
    end

    if not dap.adapters[adapter] then
        vim.notify(
            string.format("Debugging requires an %q adapter for nvim-dap", adapter),
            vim.log.levels.ERROR,
            { title = "roslyn.nvim" }
        )
        return false
    end

    local listener_id = "roslyn.nvim.test_host." .. process_id
    local finished = false

    local function remove_listeners()
        finished = true
        dap.listeners.after.attach[listener_id] = nil
        dap.listeners.after.configurationDone[listener_id] = nil
        dap.listeners.after.event_terminated[listener_id] = nil
    end

    ---@param attached boolean
    local function finish(attached)
        if finished then
            return
        end
        remove_listeners()
        vim.schedule(function()
            coroutine.resume(request_coroutine, attached)
        end)
    end

    local function is_test_host_session(session)
        return session.config.processId == process_id
    end

    dap.listeners.after.attach[listener_id] = function(session, err)
        if err and is_test_host_session(session) then
            finish(false)
        end
    end
    dap.listeners.after.configurationDone[listener_id] = function(session, err)
        if is_test_host_session(session) then
            finish(err == nil)
        end
    end
    dap.listeners.after.event_terminated[listener_id] = function(session)
        if is_test_host_session(session) then
            finish(false)
        end
    end

    local started, err = pcall(dap.run, {
        type = adapter,
        name = "Roslyn: debug tests",
        request = "attach",
        processId = process_id,
    }, { new = true })
    if not started then
        remove_listeners()
        vim.notify("Failed to start nvim-dap: " .. tostring(err), vim.log.levels.ERROR, { title = "roslyn.nvim" })
        return false
    end

    vim.defer_fn(function()
        if not finished then
            vim.notify(
                string.format("The debugger did not attach within %d seconds", attach_timeout_ms / 1000),
                vim.log.levels.ERROR,
                { title = "roslyn.nvim" }
            )
            finish(false)
        end
    end, attach_timeout_ms)

    return coroutine.yield()
end

return M
