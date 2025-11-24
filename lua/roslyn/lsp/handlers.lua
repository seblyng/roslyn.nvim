local diagnostics = require("roslyn.lsp.diagnostics")
local razor = require("roslyn.razor.types")
local razorDocumentManager = require("roslyn.razor.documentManager")

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

        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

        -- Add diagnostics when project init
        diagnostics.refresh(client)
    end,
    ["workspace/refreshSourceGeneratedDocument"] = function(_, _, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local uri = vim.api.nvim_buf_get_name(buf)
            if vim.api.nvim_buf_get_name(buf):match("^roslyn%-source%-generated://") then
                local function handler(err, result)
                    assert(not err, vim.inspect(err))
                    if vim.b[buf].resultId == result.resultId then
                        return
                    end
                    local content = result.text
                    if content == nil then
                        content = ""
                    end
                    local normalized = string.gsub(content, "\r\n", "\n")
                    local source_lines = vim.split(normalized, "\n", { plain = true })
                    vim.bo[buf].modifiable = true
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, source_lines)
                    vim.b[buf].resultId = result.resultId
                    vim.bo[buf].modifiable = false
                end

                local params = {
                    textDocument = {
                        uri = uri,
                    },
                    resultId = vim.b[buf].resultId,
                }

                ---@diagnostic disable-next-line: param-type-mismatch
                client:request("sourceGeneratedDocument/_roslyn_getText", params, handler, buf)
            end
        end
    end,
    ["workspace/_roslyn_projectNeedsRestore"] = function(_, result, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

        local function uuid()
            local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
            return string.gsub(template, "[xy]", function(c)
                local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
                return string.format("%x", v)
            end)
        end

        local token = uuid()
        result.partialResultToken = token

        local id = vim.api.nvim_create_autocmd("LspProgress", {
            callback = function(ev)
                local params = ev.data.params
                if params[1] ~= token then
                    return
                end

                vim.api.nvim_exec_autocmds("User", {
                    pattern = "RoslynRestoreProgress",
                    data = ev.data,
                })
            end,
        })

        ---@diagnostic disable-next-line: param-type-mismatch
        client:request("workspace/_roslyn_restore", result, function(err, res)
            vim.api.nvim_exec_autocmds("User", {
                pattern = "RoslynRestoreResult",
                data = {
                    token = token,
                    err = err,
                    res = res,
                },
            })

            vim.api.nvim_del_autocmd(id)
        end)

        return vim.NIL
    end,
    -- Razor Endpoints
    -- NOTE:
    -- Where these comms that are usually client -> server come server -> client
    -- roslyn wants us to query the local Html lsp and return the addtional options

    ---@param _err lsp.ResponseError
    ---@param res HtmlUpdateParams
    ---@param _ctx lsp.HandlerContext
    ---@return false
    ["razor/updateHtml"] = function(_err, res, _ctx)
        razorDocumentManager.updateDocumentText(res.textDocument.uri, res.checksum, res.text)
        return false
    end,
    --TODO: Type these returns properly

    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.DocumentColorParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/documentColor"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the color information
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.ColorPresentationParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/colorPresentation"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the color presentations
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.FoldingRangeParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/foldingRange"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the folding ranges
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param res HtmlForwardedRequest<lsp.HoverParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/hover"] = function(_err, res, _ctx)
        local htmlDocument = razorDocumentManager.findDocument(res.textDocument.uri)
        local result = htmlDocument:lspRequest("textDocument/hover", res.request)
        if not result.result then
            return vim.NIL
        end
        return result.result
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.DocumentHighlightParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/documentHighlight"] = function(_err, _res, _ctx)
        -- here we check the documentstore, and then return the document highlights
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.CompletionParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/completion"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the completion items
        return { isIncomplete = false, items = {} }
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.ReferenceParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/reference"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the references
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.ImplementationParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/Implementation"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the implementations
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.DefinitionParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/definition"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the definitions
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.SignatureHelpParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table | nil
    ["textDocument/signatureHelp"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the signature help
        return nil
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.DocumentFormattingParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/formatting"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the htmlEdits
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param _res HtmlForwardedRequest<lsp.DocumentOnTypeFormattingParams>
    ---@param _ctx lsp.HandlerContext
    ---@return table
    ["textDocument/onTypeFormatting"] = function(_err, _res, _ctx)
        -- Here we check the documentstore, and then return the htmlEdits
        return {}
    end,
    ---@param _err lsp.ResponseError
    ---@param res LogMessageParams
    ---@param _ctx lsp.HandlerContext
    ---@return true
    ["razor/log"] = function(_err, res, _ctx)
        -- TODO: once we are more stable we can use the existing log methods
        local level = razor.MessageType[res.type]
        if level == "Error" or level == "Warning" then
            vim.print(res.message)
        end
        return true
    end,
}
