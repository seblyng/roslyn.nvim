local M = {}

---@param client vim.lsp.Client
function M.refresh(client)
    for buf in pairs(client.attached_buffers) do
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
