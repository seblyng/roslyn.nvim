#!/usr/bin/env lua
-- Minimal mock LSP server for testing
-- Run with: lua test/mock_server.lua
--
-- Records solution/open and project/open notifications to a log file.
-- The log file path is specified via ROSLYN_MOCK_SERVER_LOG env var.

-- Minimal JSON encoder/decoder for our specific use case
local json = {}

function json.encode(value)
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    elseif t == "table" then
        -- Check if array or object
        local is_array = #value > 0 or next(value) == nil
        if is_array then
            local parts = {}
            for _, v in ipairs(value) do
                table.insert(parts, json.encode(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(value) do
                table.insert(parts, json.encode(tostring(k)) .. ":" .. json.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function json.decode(str)
    -- Very basic JSON decoder - handles our specific LSP messages
    local pos = 1

    local function skip_whitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parse_value()
        skip_whitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            -- String
            pos = pos + 1
            local start = pos
            while pos <= #str do
                local ch = str:sub(pos, pos)
                if ch == '"' then
                    local result = str:sub(start, pos - 1)
                    pos = pos + 1
                    -- Handle basic escape sequences
                    result = result:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
                    return result
                elseif ch == "\\" then
                    pos = pos + 2 -- Skip escaped char
                else
                    pos = pos + 1
                end
            end
        elseif c == "{" then
            -- Object
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while true do
                skip_whitespace()
                local key = parse_value()
                skip_whitespace()
                pos = pos + 1 -- skip ':'
                local value = parse_value()
                obj[key] = value
                skip_whitespace()
                if str:sub(pos, pos) == "}" then
                    pos = pos + 1
                    return obj
                end
                pos = pos + 1 -- skip ','
            end
        elseif c == "[" then
            -- Array
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while true do
                table.insert(arr, parse_value())
                skip_whitespace()
                if str:sub(pos, pos) == "]" then
                    pos = pos + 1
                    return arr
                end
                pos = pos + 1 -- skip ','
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif c:match("[%d%-]") then
            -- Number
            local start = pos
            while pos <= #str and str:sub(pos, pos):match("[%d%.eE%+%-]") do
                pos = pos + 1
            end
            return tonumber(str:sub(start, pos - 1))
        end

        return nil
    end

    return parse_value()
end

-- Server state
local log_file = os.getenv("ROSLYN_MOCK_SERVER_LOG") or "/tmp/roslyn_mock_server.log"
local debug_file = os.getenv("ROSLYN_MOCK_SERVER_DEBUG")
local notifications = {}

local function write_log()
    local f = io.open(log_file, "w")
    if f then
        f:write(json.encode(notifications))
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
    local msg = json.decode(body)
    return msg
end

local function send_response(id, result)
    local response = json.encode({
        jsonrpc = "2.0",
        id = id,
        result = result,
    })
    io.write("Content-Length: " .. #response .. "\r\n\r\n" .. response)
    io.flush()
    log_debug("Sent response: " .. response)
end

-- Clear log file on startup
write_log()
log_debug("Mock server started, log file: " .. log_file)

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
        send_response(msg.id, json.encode(nil))
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
