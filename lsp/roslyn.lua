local utils = require("roslyn.sln.utils")

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

local function on_init_sln(solution)
    return function(client)
        vim.g.roslyn_nvim_selected_solution = solution
        vim.notify("Initializing Roslyn client for " .. solution, vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("solution/open", {
            solution = vim.uri_from_fname(solution),
        })
    end
end

local function on_init_projects(projects)
    return function(client)
        vim.notify("Initializing Roslyn client for projects", vim.log.levels.INFO, { title = "roslyn.nvim" })
        client:notify("project/open", {
            projects = vim.tbl_map(function(file)
                return vim.uri_from_fname(file)
            end, projects),
        })
    end
end

return {
    filetypes = { "cs" },
    cmd = default_cmd(),
    cmd_env = {
        Configuration = vim.env.Configuration or "Debug",
    },
    capabilities = {
        textDocument = {
            -- HACK: Doesn't show any diagnostics if we do not set this to true
            diagnostic = {
                dynamicRegistration = true,
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        local root_dir = utils.root_dir(bufnr)
        if root_dir then
            on_dir(root_dir)
        end
    end,
    on_init = {
        function(client)
            local config = require("roslyn.config").get()
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if config.lock_target and selected_solution then
                return on_init_sln(selected_solution)(client)
            end

            local bufnr = vim.api.nvim_get_current_buf()
            local files = utils.find_files_with_extensions(client.config.root_dir, { ".sln", ".slnx", ".slnf" })

            local solution = utils.predict_target(bufnr, files)
            if solution then
                return on_init_sln(solution)(client)
            end

            local csproj = utils.find_files_with_extensions(client.config.root_dir, { ".csproj" })
            if #csproj > 0 then
                return on_init_projects(csproj)(client)
            end

            if selected_solution then
                return on_init_sln(selected_solution)(client)
            end
        end,
    },
    on_exit = {
        function()
            vim.g.roslyn_nvim_selected_solution = nil
            vim.schedule(function()
                require("roslyn.roslyn_emitter"):emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
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
