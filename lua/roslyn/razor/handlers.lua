---@type table<vim.lsp.protocol.Method.ClientToServer, any>
local nil_responses = {
    ["textDocument/hover"] = true,
}

---@generic T
---@param _err any
---@param res HtmlForwardedRequest<T>
---@param ctx lsp.HandlerContext
local function forward(_err, res, ctx)
    local razorDocumentManager = require("roslyn.razor.documentManager")
    local uri = res.textDocument and res.textDocument.uri
        or ctx.params and ctx.params.textDocument and ctx.params.textDocument.uri
    assert(uri, string.format("No uri found in forwarded request for method %s", ctx.method))
    local htmlDocument = razorDocumentManager:getDocument(uri, res.checksum)
    if not htmlDocument then
        return nil_responses[ctx.method] and vim.NIL or {}
    end
    local result = htmlDocument:lspRequest(ctx.method, res.request or ctx.params)
    if not result then
        return nil_responses[ctx.method] and vim.NIL or {}
    end
    return result
end

local function log(_err, res, _ctx)
    local razor = require("roslyn.razor.types")
    -- TODO: once we are more stable we can use the existing log methods
    local level = razor.MessageType[res.type]
    if level == "Error" or level == "Warning" then
        vim.print(res.message)
    end
    return true
end

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
