local HtmlDocument = require("roslyn.razor.htmlDocument")

local M = {}

local virtualHtmlSuffix = "__virtual.html"

---@type table<string, HtmlDocument>
M.htmlDocuments = {}

--- @param uri string
--- @param checksum string
--- @param content string
function M.updateDocumentText(uri, checksum, content)
    local doc = M.findDocument(uri)
    if not doc then
        doc = HtmlDocument.new(uri, checksum, content)
        M.htmlDocuments[doc.path] = doc
    end
    doc:setContent(checksum, content)
    return doc
end

--- @param uri string
--- @return HtmlDocument
function M.findDocument(uri)
    if not uri:match(virtualHtmlSuffix .. "$") then
        uri = uri .. virtualHtmlSuffix
    end
    return M.htmlDocuments[uri]
end

--- @param uri string
function M.getContent(uri)
    local doc = M.findDocument(uri)
    assert(doc, "Document not found: " .. uri)
    return doc:getContent()
end

--- @param uri string
function M.closeDocument(uri)
    local doc = M.findDocument(uri)
    assert(doc, "Document not found: " .. uri)
    doc:close()
    M.htmlDocuments[uri] = nil
end

function M.dump()
    vim.print(M.htmlDocuments)
end

return M
