#!/usr/bin/env -S nvim -l
-- Minimal mock LSP server for testing
-- Run with: nvim -l test/mock_server.lua
--
-- Records solution/open and project/open notifications to a log file.
-- The log file path is specified via ROSLYN_MOCK_SERVER_LOG env var.

-- Server state
local log_file = os.getenv("ROSLYN_MOCK_SERVER_LOG") or "/tmp/roslyn_mock_server.log"
local debug_file = os.getenv("ROSLYN_MOCK_SERVER_DEBUG")
local notifications = {}

local function read_existing_notifications()
    local f = io.open(log_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content and content ~= "" then
            local ok, existing = pcall(vim.json.decode, content)
            if ok and existing and type(existing) == "table" then
                return existing
            end
        end
    end
    return {}
end

local function write_log()
    local f = io.open(log_file, "w")
    if f then
        f:write(vim.json.encode(notifications))
        f:close()
    end
end

local function log_debug(msg)
    if debug_file then
        local f = io.open(debug_file, "a")
        if f then
            f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
            f:close()
        end
    end
end

local function read_headers()
    local headers = {}
    while true do
        local line = io.read("*l")
        if not line then
            return nil
        end
        -- Remove \r if present
        line = line:gsub("\r$", "")
        if line == "" then
            break
        end
        local key, value = line:match("^([^:]+):%s*(.+)$")
        if key then
            headers[key:lower()] = value
        end
    end
    return headers
end

local function read_message()
    local headers = read_headers()
    if not headers then
        return nil
    end
    local content_length = tonumber(headers["content-length"])
    if not content_length then
        log_debug("No content-length header")
        return nil
    end
    local body = io.read(content_length)
    if not body then
        log_debug("Failed to read body")
        return nil
    end
    log_debug("Raw body: " .. body)
    local ok, msg = pcall(vim.json.decode, body)
    if not ok then
        log_debug("Failed to decode JSON: " .. tostring(msg))
        return nil
    end
    return msg
end

local function send_response(id, result)
    local response = vim.json.encode({
        jsonrpc = "2.0",
        id = id,
        result = result,
    })
    io.write("Content-Length: " .. #response .. "\r\n\r\n" .. response)
    io.flush()
    log_debug("Sent response: " .. response)
end

-- Read existing notifications on startup (to support multiple server instances)
notifications = read_existing_notifications()
log_debug("Mock server started, log file: " .. log_file .. ", existing notifications: " .. #notifications)

-- Main message loop
while true do
    local msg = read_message()
    if not msg then
        log_debug("No message received, exiting")
        break
    end

    log_debug("Received method: " .. tostring(msg.method))

    if msg.method == "initialize" then
        log_debug("Handling initialize")
        send_response(msg.id, {
            capabilities = {
                textDocumentSync = 1,
            },
            serverInfo = {
                name = "roslyn-mock-server",
                version = "0.0.1",
            },
        })
    elseif msg.method == "initialized" then
        log_debug("Handling initialized")
        -- Notification, no response needed
    elseif msg.method == "shutdown" then
        log_debug("Handling shutdown")
        send_response(msg.id, vim.NIL)
    elseif msg.method == "exit" then
        log_debug("Handling exit")
        break
    elseif msg.method == "solution/open" then
        log_debug("Handling solution/open")
        table.insert(notifications, {
            method = "solution/open",
            params = msg.params,
        })
        write_log()
    elseif msg.method == "project/open" then
        log_debug("Handling project/open")
        table.insert(notifications, {
            method = "project/open",
            params = msg.params,
        })
        write_log()
    elseif msg.id then
        -- Unknown request, send empty response
        log_debug("Unknown request: " .. tostring(msg.method))
        send_response(msg.id, {})
    else
        -- Unknown notification, ignore
        log_debug("Unknown notification: " .. tostring(msg.method))
    end
end

log_debug("Mock server exiting")
