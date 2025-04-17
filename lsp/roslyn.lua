local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

---@return string[]?
local function default_cmd()
    local data = vim.fn.stdpath("data") --[[@as string]]

    local mason_path = vim.fs.joinpath(data, "mason", "bin", "roslyn")
    local mason_installation = iswin and string.format("%s.cmd", mason_path) or mason_path

    if vim.uv.fs_stat(mason_installation) == nil then
        return nil
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
    before_init = function(_, config)
        local on_exit = type(config.on_exit) == "table" and config.on_exit or { config.on_exit }
        config.on_exit = {
            function()
                vim.g.roslyn_nvim_selected_solution = nil
                vim.schedule(function()
                    require("roslyn.roslyn_emitter"):emit("stopped")
                    vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
                end)
            end,
            unpack(on_exit),
        }
        P(config)
    end,
    commands = {
        ["roslyn.client.fixAllCodeAction"] = function(data, ctx)
            require("roslyn.lsp_commands").fix_all_code_action(data, ctx)
        end,
        ["roslyn.client.nestedCodeAction"] = function(data, ctx)
            require("roslyn.lsp_commands").nested_code_action(data, ctx)
        end,
        ["roslyn.client.completionComplexEdit"] = function(data)
            require("roslyn.lsp_commands").completion_complex_edit(data)
        end,
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
