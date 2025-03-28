local roslyn_emitter = require("roslyn.roslyn_emitter")
local M = {}

---@param bufnr integer
---@param root_dir string
---@param on_init fun(client: vim.lsp.Client)
function M.start(bufnr, root_dir, on_init)
    local config = vim.lsp.config.roslyn
    config.root_dir = root_dir
    config.handlers = vim.tbl_deep_extend("force", {
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
    }, config.handlers or {})
    config.on_init = function(client, initialize_result)
        if config.on_init then
            config.on_init(client, initialize_result)
        end
        on_init(client)

        local lsp_commands = require("roslyn.lsp_commands")
        lsp_commands.fix_all_code_action(client)
        lsp_commands.nested_code_action(client)
        lsp_commands.completion_complex_edit()
    end

    config.on_exit = function(code, signal, client_id)
        vim.g.roslyn_nvim_selected_solution = nil
        vim.schedule(function()
            roslyn_emitter:emit("stopped")
            vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
        end)
        if config.on_exit then
            config.on_exit(code, signal, client_id)
        end
    end

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        pattern = "roslyn-source-generated://*",
        callback = function()
            local uri = vim.fn.expand("<amatch>")
            local buf = vim.api.nvim_get_current_buf()
            vim.bo[buf].modifiable = true
            vim.bo[buf].swapfile = false
            vim.bo[buf].buftype = "nowrite"
            -- This triggers FileType event which should fire up the lsp client if not already running
            vim.bo[buf].filetype = "cs"
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            assert(client, "Must have a `roslyn` client to load roslyn source generated file")

            local content
            local function handler(err, result)
                assert(not err, vim.inspect(err))
                content = result.text
                if content == nil then
                    content = ""
                end
                local normalized = string.gsub(content, "\r\n", "\n")
                local source_lines = vim.split(normalized, "\n", { plain = true })
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, source_lines)
                vim.b[buf].resultId = result.resultId
                vim.bo[buf].modifiable = false
            end

            local params = {
                textDocument = {
                    uri = uri,
                },
                resultId = nil,
            }

            client:request("sourceGeneratedDocument/_roslyn_getText", params, handler, buf)
            -- Need to block. Otherwise logic could run that sets the cursor to a position
            -- that's still missing.
            vim.wait(1000, function()
                return content ~= nil
            end)
        end,
    })

    vim.lsp.start(config, { bufnr = bufnr })
end

---@param solution string
function M.on_init_sln(solution)
    return function(client)
        vim.g.roslyn_nvim_selected_solution = solution
        vim.notify("Initializing Roslyn client for " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("solution/open", {
            solution = vim.uri_from_fname(solution),
        })
    end
end

---@param files string[]
function M.on_init_project(files)
    return function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, files),
        })
    end
end

return M
