local M = {}

---@param client vim.lsp.Client
function M.refresh(client)
    local buffers = vim.lsp.get_buffers_by_client_id(client.id)
    for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_loaded(buf) then
            client:request(
                vim.lsp.protocol.Methods.textDocument_diagnostic,
                { textDocument = vim.lsp.util.make_text_document_params(buf) },
                nil,
                buf
            )
        end
    end
end

return M
