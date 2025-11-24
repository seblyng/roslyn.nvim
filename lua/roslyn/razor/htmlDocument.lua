---@type HtmlDocument
---@diagnostic disable-next-line: missing-fields
local document = {}

local virtualHtmlSuffix = "__virtual.html"

---@diagnostic disable-next-line: inject-field
document.__index = document

--- @class HtmlDocument
--- @field path string
--- @field buf number
--- @field content string
--- @field checksum string
--- @field new fun(uri: string, checksum: string, content: string): HtmlDocument
--- @field update fun(self: HtmlDocument, path: string, buf: number, checksum: string)
--- @field getChecksum fun(self: HtmlDocument): string
--- @field getContent fun(self: HtmlDocument): string
--- @field setContent fun(self: HtmlDocument, checksum: string, content: string)
--- @field close fun(self: HtmlDocument)
--- @field lspRequest fun(self: HtmlDocument, method: string, params: table): any

---@param uri string
---@param checksum string
---@param content string
---@return HtmlDocument
function document.new(uri, checksum, content)
    local self = setmetatable({}, document)
    self.path = uri .. virtualHtmlSuffix
    self.content = content
    self.checksum = checksum
    self.buf = vim.uri_to_bufnr(self.path)
    -- TODO: set nowrite etc
    return self
end

function document:getContent()
    return self.content
end

function document:getChecksum()
    return self.checksum
end

function document:setContent(checksum, content)
    self.checksum = checksum
    self.content = content
    if self.buf then
        vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, vim.split(content, "\n"))
    end
end

function document:close()
    vim.api.nvim_buf_delete(self.buf, { force = true })
end

function document:lspRequest(method, params)
    local clients = vim.lsp.get_clients({ bufnr = self.buf, name = "html" })
    assert(#clients == 1, "Expected exactly one HTML LSP client")
    if not params.textDocument.uri:match(virtualHtmlSuffix .. "$") then
        params.textDocument.uri = params.textDocument.uri .. virtualHtmlSuffix
    end
    -- TODO: Make this async
    local result, err = clients[1]:request_sync(method, params, nil, self.buf)
    assert(not err, vim.inspect(err))
    return result
end

return document
