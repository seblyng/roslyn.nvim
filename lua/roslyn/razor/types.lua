local M = {}

---@class HtmlForwardedRequest<T>: { checksum: string, textDocument: lsp.TextDocumentIdentifier,  request: T }

---@class HtmlUpdateParams : HtmlForwardedRequest
---@field textDocument lsp.TextDocumentIdentifier
---@field checksum string
---@field text string

---@enum MessageType
M.MessageType = {
    [1] = "Error",
    [2] = "Warning",
    [3] = "Info",
    [4] = "Log",
    [5] = "Debug",
}

--- Parameters for a log message
---@class LogMessageParams
---@field type MessageType
---@field message string

return M
