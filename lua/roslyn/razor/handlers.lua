---@type table<vim.lsp.protocol.Method.ClientToServer, any>
local nil_responses = {
    ["textDocument/hover"] = true,
}

---@generic T
---@param err lsp.ResponseError?
---@param res HtmlForwardedRequest<T>
---@param ctx lsp.HandlerContext
---@param config table?
local function forward(err, res, ctx, config)
    if not res or not res.textDocument or not res.textDocument.uri or not res.checksum then
        -- Does not seem to be a request from roslyn. Run the default handler instead
        vim.lsp.handlers[ctx.method](err, res, ctx, config)
        return
    end

    local razorDocumentManager = require("roslyn.razor.documentManager")
    local htmlDocument = razorDocumentManager:getDocument(res.textDocument.uri, res.checksum)
    if not htmlDocument then
        return nil_responses[ctx.method] and vim.NIL or {}
    end
    local result = htmlDocument:lspRequest(ctx.method, res.request)
    if not result then
        return nil_responses[ctx.method] and vim.NIL or {}
    end
    return result
end

---@param _err lsp.ResponseError
---@param res LogMessageParams
---@param _ctx lsp.HandlerContext
---@return true
local function log(_err, res, _ctx)
    local razor = require("roslyn.razor.types")
    -- TODO: once we are more stable we can use the existing log methods
    local level = razor.MessageType[res.type]
    if level == "Error" or level == "Warning" then
        vim.print(res.message)
    end
    return true
end

---@param _err lsp.ResponseError
---@param res HtmlUpdateParams
---@param _ctx lsp.HandlerContext
---@return false
local function update_html(_err, res, _ctx)
    local razorDocumentManager = require("roslyn.razor.documentManager")
    razorDocumentManager:updateDocumentText(res.textDocument.uri, res.checksum, res.text)
    return false
end

return {
    forward = forward,
    log = log,
    html_update = update_html,
}
