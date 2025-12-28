---@type HtmlDocument
---@diagnostic disable-next-line: missing-fields
local document = {}

---@diagnostic disable-next-line: inject-field
document.__index = document

--- @class HtmlDocument
--- @field path string
--- @field buf number
--- @field content string
--- @field checksum string
--- @field new fun(uri: string): HtmlDocument
--- @field update fun(self: HtmlDocument, path: string, buf: number, checksum: string)
--- @field getChecksum fun(self: HtmlDocument): string
--- @field getContent fun(self: HtmlDocument): string
--- @field setContent fun(self: HtmlDocument, checksum: string, content: string)
--- @field close fun(self: HtmlDocument)
--- @field lspRequest async fun(self: HtmlDocument, method: string, params: table): any

---@param uri string
---@return HtmlDocument
function document.new(uri)
    local self = setmetatable({}, document)
    self.path = uri .. require("roslyn.razor.types").virtualHtmlSuffix
    self.buf = vim.uri_to_bufnr(self.path)
    -- NOTE: We set this in an autocmd because otherwise the LSP does not attach to the buffer

    vim.bo[self.buf].filetype = "html"
    vim.bo[self.buf].buftype = "nowrite"
    vim.bo[self.buf].swapfile = false
    vim.bo[self.buf].bufhidden = "hide"
    vim.bo[self.buf].undolevels = -1

    vim.api.nvim_create_autocmd("LspAttach", {
        buffer = self.buf,
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            assert(client, "LSP client id is not valid")
            if client.name == "html" then
                vim.bo[ev.buf].buftype = "nowrite"
                vim.bo[ev.buf].syntax = "off"
                vim.api.nvim_del_autocmd(ev.id)
            end
        end,
    })
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
        assert(vim.api.nvim_buf_is_valid(self.buf), "Virtual HTML Document buffer is not valid")
        vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, vim.split(content, "\n"))
    end
end

function document:close()
    if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
        vim.api.nvim_buf_delete(self.buf, { force = true })
    end
end

function document:lspRequest(method, params)
    local clients = vim.lsp.get_clients({ bufnr = self.buf, name = require("roslyn.razor.types").html_lsp_name })
    if #clients ~= 1 then
        return nil
    end
    if not params.textDocument.uri:match(require("roslyn.razor.types").virtualHtmlSuffix .. "$") then
        params.textDocument.uri = params.textDocument.uri .. require("roslyn.razor.types").virtualHtmlSuffix
    end

    local co = coroutine.running()

    if co == nil then
        error("document.lspRequest must be called inside a coroutine")
    end

    local status = clients[1]:request(method, params, function(err, result, _ctx, _config)
        coroutine.resume(co, result, err)
    end, self.buf)

    if not status then
        error("LSP client was shutdown")
    end

    ---@type any, lsp.ResponseError
    local result, err = coroutine.yield(co)

    assert(not err, vim.inspect(err or "No Result from forwarded LSP Request"))
    return result
end

return document
