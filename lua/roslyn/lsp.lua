local M = {}

local has_resolved_legacy_path = false

local has_resolved_on_methods = false
local _on_init, _on_exit

-- TODO(seb): Remove this in a couple of months or so
local function try_resolve_legacy_path()
    local legacy_path = vim.fs.joinpath(vim.fn.stdpath("data"), "roslyn", "Microsoft.CodeAnalysis.LanguageServer.dll")

    if vim.uv.fs_stat(legacy_path) and not vim.lsp.config.roslyn.cmd then
        vim.notify(
            "The default cmd location of roslyn is deprecated.\nEither download through mason, or specify the location through `vim.lsp.config.roslyn.cmd` as specified in the README",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
        vim.lsp.config.roslyn.cmd = {
            "dotnet",
            legacy_path,
            "--logLevel=Information",
            "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.get_log_path()),
            "--stdio",
        }
    end

    return nil
end

---@param bufnr integer
---@param root_dir string
---@param on_init fun(client: vim.lsp.Client)
function M.start(bufnr, root_dir, on_init)
    -- TODO(seb): This is not so nice, but I think it works
    if not has_resolved_on_methods then
        _on_init, _on_exit = vim.lsp.config.roslyn.on_init, vim.lsp.config.roslyn.on_exit
        has_resolved_on_methods = true
    end

    if not has_resolved_legacy_path then
        try_resolve_legacy_path()
    end

    -- TODO(seb): Remove this in a couple of months or so
    if not vim.lsp.config.roslyn.cmd then
        return vim.notify(
            "No `cmd` for roslyn detected.\nEither install through mason or specify the path yourself through `vim.lsp.config.roslyn.cmd`",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end

    vim.lsp.config("roslyn", {
        root_dir = root_dir,
        on_init = function(client, initialize_result)
            if _on_init then
                _on_init(client, initialize_result)
            end
            on_init(client)

            local lsp_commands = require("roslyn.lsp_commands")
            lsp_commands.fix_all_code_action(client)
            lsp_commands.nested_code_action(client)
            lsp_commands.completion_complex_edit()
        end,
        on_exit = function(code, signal, client_id)
            vim.g.roslyn_nvim_selected_solution = nil
            vim.schedule(function()
                require("roslyn.roslyn_emitter"):emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
            if _on_exit then
                _on_exit(code, signal, client_id)
            end
        end,
    })

    vim.lsp.start(vim.lsp.config.roslyn, { bufnr = bufnr })
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
