local M = {}

---@class HtmlForwardedRequest
---@field textDocument lsp.TextDocumentIdentifier
---@field checksum string

---@class HtmlUpdateParams : HtmlForwardedRequest
---@field text string

---@class HtmlForwardedRequestHover : HtmlForwardedRequest
---@field request lsp.HoverParams

---@class HtmlForwardedRequestDocumentColor : HtmlForwardedRequest
---@field request lsp.DocumentColorParams

---@class HtmlForwardedRequestColorPresentation : HtmlForwardedRequest
---@field request lsp.ColorPresentationParams

---@class HtmlForwardedRequestFoldingRange : HtmlForwardedRequest
---@field request lsp.FoldingRangeParams

---@class HtmlForwardedRequestDocumentHighlight : HtmlForwardedRequest
---@field request lsp.DocumentHighlightParams

---@class HtmlForwardedRequestCompletion : HtmlForwardedRequest
---@field request lsp.CompletionParams

---@class HtmlForwardedRequestReference : HtmlForwardedRequest
---@field request lsp.ReferenceParams

---@class HtmlForwardedRequestImplementation : HtmlForwardedRequest
---@field request lsp.TextDocumentPositionParams

---@class HtmlForwardedRequestDefinition : HtmlForwardedRequest
---@field request lsp.TextDocumentPositionParams

---@class HtmlForwardedRequestSignatureHelp : HtmlForwardedRequest
---@field request lsp.SignatureHelpParams

---@class HtmlForwardedRequestFormatting : HtmlForwardedRequest
---@field request lsp.DocumentFormattingParams

---@class HtmlForwardedRequestOnTypeFormatting : HtmlForwardedRequest
---@field request lsp.DocumentOnTypeFormattingParams

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
