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
        vim.notify("Roslyn project initialization complete", vim.log.levels.INFO, { title = "roslyn.nvim" })

        ---NOTE: This is used by rzls.nvim for init
        vim.api.nvim_exec_autocmds("User", { pattern = "RoslynInitialized", modeline = false })
        _G.roslyn_initialized = true

        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        local buffers = vim.lsp.get_buffers_by_client_id(ctx.client_id)
        for _, buf in ipairs(buffers) do
            local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
            client:request("textDocument/diagnostic", params, nil, buf)
        end
    end,
    ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
        vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR, {
            title = "roslyn.nvim",
        })
        return vim.NIL
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

                client:request("sourceGeneratedDocument/_roslyn_getText", params, handler, buf)
            end
        end
    end,
}
