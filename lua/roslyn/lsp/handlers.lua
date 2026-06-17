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
        if not require("roslyn.config").get().silent then
            vim.notify("Roslyn project initialization complete", vim.log.levels.INFO, { title = "roslyn.nvim" })
        end

        vim.api.nvim_exec_autocmds("User", {
            pattern = "RoslynInitialized",
            modeline = false,
            data = { client_id = ctx.client_id },
        })

        -- lsp provides stale diagnostics before it is fully initialized
        local lsp_client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        for bufnr in pairs(lsp_client.attached_buffers) do
            vim.lsp.diagnostic._refresh(bufnr, ctx.client_id)
        end
    end,
    ["workspace/textDocumentContent/refresh"] = function(_, _, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local uri = vim.api.nvim_buf_get_name(buf)
            if vim.api.nvim_buf_is_loaded(buf) and uri:match("^roslyn%-source%-generated://") then
                ---@param result lsp.TextDocumentContentResult
                local function handler(err, result)
                    assert(not err, vim.inspect(err))
                    local content = result.text or ""
                    if content == vim.NIL then
                        content = ""
                    end
                    local normalized = string.gsub(content, "\r\n", "\n")
                    local source_lines = vim.split(normalized, "\n", { plain = true })
                    vim.bo[buf].modifiable = true
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, source_lines)
                    vim.bo[buf].modifiable = false
                    vim.bo[buf].modified = false
                end

                ---@type lsp.TextDocumentContentRefreshParams
                local params = {
                    uri = uri,
                }

                client:request("workspace/textDocumentContent", params, handler, buf)
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
