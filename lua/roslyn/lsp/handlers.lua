local diagnostics = require("roslyn.lsp.diagnostics")

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
        local store = require("roslyn.store")
        if not store.is_initialized(ctx.client_id) then
            store.set_initialized(ctx.client_id)
            if not require("roslyn.config").get().silent then
                local solution = store.get(ctx.client_id)
                local elapsed_ms = store.get_init_elapsed_ms(ctx.client_id)

                local sln_name = solution and vim.fn.fnamemodify(solution, ":t:r") or "project"
                local time_str = elapsed_ms and string.format("%.1f sec", elapsed_ms / 1000) or "?"

                vim.notify(
                    sln_name .. "\ninitialization complete in " .. time_str,
                    vim.log.levels.INFO,
                    { title = "roslyn.nvim" }
                )
            end
        end

        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

        vim.api.nvim_exec_autocmds("User", {
            pattern = "RoslynInitialized",
            modeline = false,
            data = { client_id = ctx.client_id },
        })

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
    -- TODO: This is no longer needed with latest roslyn: https://github.com/dotnet/roslyn/pull/81233
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
