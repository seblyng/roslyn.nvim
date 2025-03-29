local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

-- TODO(seb): Remove this in a couple of months after release
local function try_resolve_legacy_path()
    local legacy_path = vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")

    if vim.uv.fs_stat(legacy_path) then
        vim.notify(
            "The default cmd location of roslyn is deprecated.\nEither download through mason, or specify the location through `vim.lsp.config.roslyn.cmd` as specified in the README",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
        return {
            "dotnet",
            legacy_path,
            "--logLevel=Information",
            "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
            "--stdio",
        }
    end

    return nil
end

---@return string[]?
local function default_cmd()
    local data = vim.fn.stdpath("data") --[[@as string]]

    local mason_path = vim.fs.joinpath(data, "mason", "bin", "roslyn")
    local mason_installation = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_installation) == nil then
        return try_resolve_legacy_path()
    end

    return {
        mason_installation,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
        "--stdio",
    }
end

return {
    cmd = default_cmd(),
    capabilities = {
        textDocument = {
            -- HACK: Doesn't show any diagnostics if we do not set this to true
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    },
    handlers = {
        ["workspace/projectInitializationComplete"] = function(_, _, ctx)
            vim.notify("Roslyn project initialization complete", vim.log.levels.INFO, { title = "roslyn.nvim" })

            ---NOTE: This is used by rzls.nvim for init
            vim.api.nvim_exec_autocmds("User", { pattern = "RoslynInitialized", modeline = false })
            _G.roslyn_initialized = true

            local buffers = vim.lsp.get_buffers_by_client_id(ctx.client_id)
            for _, buf in ipairs(buffers) do
                vim.lsp.util._refresh("textDocument/diagnostic", { bufnr = buf })
            end
        end,
        ["workspace/_roslyn_projectHasUnresolvedDependencies"] = function()
            vim.notify("Detected missing dependencies. Run dotnet restore command.", vim.log.levels.ERROR, {
                title = "roslyn.nvim",
            })
            return vim.NIL
        end,
        ["workspace/_roslyn_projectNeedsRestore"] = function(_, result, ctx)
            local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

            client:request("workspace/_roslyn_restore", result, function(err, response)
                if err then
                    vim.notify(err.message, vim.log.levels.ERROR, { title = "roslyn.nvim" })
                end
                if response then
                    for _, v in ipairs(response) do
                        vim.notify(v.message, vim.log.levels.INFO, { title = "roslyn.nvim" })
                    end
                end
            end)

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
    },
}
