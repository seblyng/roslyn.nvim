return {
    ["client/registerCapability"] = function(err, res, ctx)
        if require("roslyn.config").get().filewatching == "off" then
            for _, reg in ipairs(res.registrations) do
                if reg.method == "workspace/didChangeWatchedFiles" then
                    reg.registerOptions.watchers = {}
                end
            end
        end
        return vim.lsp.handlers["client/registerCapability"](err, res, ctx)
    end,
    ["workspace/projectInitializationComplete"] = function(_, _, ctx)
        -- `vim.lsp.diagnostic._refresh` is not available in nightly. However, this is no longer needed
        -- in nightly after https://github.com/neovim/neovim/pull/40623
        if vim.fn.has("nvim-0.13") == 0 then
            local lsp_client = assert(vim.lsp.get_client_by_id(ctx.client_id))
            for bufnr in pairs(lsp_client.attached_buffers) do
                vim.lsp.diagnostic._refresh(bufnr, ctx.client_id)
            end
        end
    end,
    ["workspace/textDocumentContent/refresh"] = function(_, _, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local uri = vim.api.nvim_buf_get_name(buf)
            if vim.api.nvim_buf_is_loaded(buf) and uri:match("^roslyn%-source%-generated://") then
                require("roslyn.utils").populate_virtual_buffer_content(client, uri, buf)
            end
        end

        ---https://github.com/neovim/nvim-lspconfig/pull/4474
        ---Avoid using vim.lsp.diagnostic._refresh since it is removed from nightly
        local capabilities = vim.iter(client.dynamic_capabilities.capabilities.diagnosticProvider)
            :map(function(cap)
                return cap.registerOptions.identifier
            end)
            :totable()

        for buf, _ in pairs(client.attached_buffers) do
            if vim.api.nvim_buf_is_loaded(buf) then
                for _, cap in pairs(capabilities) do
                    client:request(vim.lsp.protocol.Methods.textDocument_diagnostic, {
                        identifier = cap,
                        textDocument = vim.lsp.util.make_text_document_params(buf),
                    }, nil, buf)
                end
            end
        end

        return vim.NIL
    end,
    -- NOTE: Razor End Points
    -- Where these comms that are usually client -> server come server -> client
    -- roslyn wants us to query the local Html LS and return the additional options
    ["razor/updateHtml"] = require("roslyn.razor.handlers").html_update,
    ["razor/log"] = require("roslyn.razor.handlers").log,

    ["textDocument/documentColor"] = require("roslyn.razor.handlers").forward,
    ["textDocument/colorPresentation"] = require("roslyn.razor.handlers").forward,
    ["textDocument/foldingRange"] = require("roslyn.razor.handlers").forward,
    ["textDocument/hover"] = require("roslyn.razor.handlers").forward,
    ["textDocument/documentHighlight"] = require("roslyn.razor.handlers").forward,
    ["textDocument/completion"] = require("roslyn.razor.handlers").forward,
    ["textDocument/reference"] = require("roslyn.razor.handlers").forward,
    ["textDocument/implementation"] = require("roslyn.razor.handlers").forward,
    ["textDocument/definition"] = require("roslyn.razor.handlers").forward,
    ["textDocument/signatureHelp"] = require("roslyn.razor.handlers").forward,
    ["textDocument/formatting"] = require("roslyn.razor.handlers").forward,
    ["textDocument/onTypeFormatting"] = require("roslyn.razor.handlers").forward,
}
