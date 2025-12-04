local HtmlDocument = require("roslyn.razor.htmlDocument")

local M = {}

---@type table<string, HtmlDocument>
M.htmlDocuments = {}

---@type table<string, boolean>
M.pendingUpdates = {}

--- @private
--- @param uri string
--- @return HtmlDocument?
local function findDocument(uri)
    if not uri:match(require("roslyn.razor.types").virtualHtmlSuffix .. "$") then
        uri = uri .. require("roslyn.razor.types").virtualHtmlSuffix
    end
    return M.htmlDocuments[uri]
end

--- @param uri string
--- @param checksum string
--- @param content string
function M:updateDocumentText(uri, checksum, content)
    local doc = findDocument(uri)
    if not doc then
        doc = HtmlDocument.new(uri)
        M.htmlDocuments[doc.path] = doc
    end
    self.pendingUpdates[doc.path] = true
    doc:setContent(checksum, content)
    self.pendingUpdates[doc.path] = nil
    return doc
end

--- @param uri string
--- @param checksum? string
--- @return HtmlDocument?
function M:getDocument(uri, checksum)
    local doc = findDocument(uri)
    if not doc then
        return nil
    end

    if checksum and doc:getChecksum() ~= checksum then
        vim.notify(
            string.format(
                "Checksum mismatch for document: %s (expected: %s, got: %s)",
                uri,
                checksum,
                doc:getChecksum()
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    if checksum then
        local pendingUpdate = self.pendingUpdates[doc.path]
        if pendingUpdate then
            vim.wait(5000, function()
                return doc:getChecksum() == checksum
            end)
        end
    end

    vim.wait(5000, function()
        return vim.lsp.get_clients({ bufnr = doc.buf, name = require("roslyn.razor.types").html_lsp_name })[1] ~= nil
    end)

    return doc
end

--- @param uri string
function M.getContent(uri)
    local doc = findDocument(uri)
    assert(doc, "GetContent: Document not found: " .. uri)
    return doc:getContent()
end

--- @param uri string
function M.closeDocument(uri)
    local doc = findDocument(uri)
    assert(doc, "Close: Document not found: " .. uri)
    doc:close()
    M.htmlDocuments[uri] = nil
end

function M.dump()
    vim.print(M.htmlDocuments)
end

return M
