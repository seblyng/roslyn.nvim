local M = {}

local has_resolved_legacy_path = false

local has_resolved_on_methods = false
local _on_init

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
---@param roslyn_on_init fun(client: vim.lsp.Client)
function M.start(bufnr, root_dir, roslyn_on_init)
    -- TODO(seb): This is not so nice, but I think it works
    if not has_resolved_on_methods then
        _on_init = vim.lsp.config.roslyn.on_init
        has_resolved_on_methods = true
    end

    if not has_resolved_legacy_path then
        try_resolve_legacy_path()
        has_resolved_legacy_path = true
    end

    -- TODO(seb): Remove this in a couple of months or so
    if not vim.lsp.config.roslyn.cmd then
        return vim.notify(
            "No `cmd` for roslyn detected.\nEither install through mason or specify the path yourself through `vim.lsp.config.roslyn.cmd`",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end

    local on_init = type(_on_init) == "table" and _on_init or { _on_init }

    vim.lsp.config("roslyn", {
        root_dir = root_dir,
        on_init = {
            roslyn_on_init,
            unpack(on_init),
        },
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
