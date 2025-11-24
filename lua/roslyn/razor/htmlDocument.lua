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

---@param uri string
---@param checksum string
---@param content string
---@return HtmlDocument
function document.new(uri, checksum, content)
    local self = setmetatable({}, document)
    self.path = uri .. virtualHtmlSuffix
    self.content = content
    self.checksum = checksum
    -- TODO: Create buffers
    self.buf = nil
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
    -- TODO: Update buffer contents
end

return document
