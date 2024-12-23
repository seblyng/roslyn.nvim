local utils = require("roslyn.sln.utils")

---@param buf number
---@return boolean
local function valid_buffer(buf)
    local bufname = vim.api.nvim_buf_get_name(buf)
    return vim.bo[buf].buftype ~= "nofile"
        and (
            bufname:match("^/")
            or bufname:match("^[a-zA-Z]:")
            or bufname:match("^zipfile://")
            or bufname:match("^tarfile:")
            or bufname:match("^roslyn%-source%-generated://")
        )
end

local M = {}

---@param config? RoslynNvimConfig
function M.setup(config)
    local roslyn_config = require("roslyn.config").setup(config)
    local roslyn_lsp = require("roslyn.lsp")

    vim.treesitter.language.register("c_sharp", "csharp")

    require("roslyn.commands").create_roslyn_commands()

    vim.api.nvim_create_autocmd({ "FileType" }, {
        group = vim.api.nvim_create_augroup("Roslyn", { clear = true }),
        pattern = { "cs", "roslyn-source-generated://*" },
        callback = function(opt)
            if not valid_buffer(opt.buf) then
                return
            end

            -- Lock the target and always start with the currently selected solution
            if roslyn_config.lock_target and vim.g.roslyn_nvim_selected_solution then
                local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
                return roslyn_lsp.start(opt.buf, sln_dir, roslyn_lsp.on_init_sln)
            end

            vim.schedule(function()
                local root = utils.root(opt.buf)
                vim.b.roslyn_root = root

                local solution = utils.predict_target(root)
                if solution then
                    vim.g.roslyn_nvim_selected_solution = solution
                    return roslyn_lsp.start(opt.buf, vim.fs.dirname(solution), roslyn_lsp.on_init_sln)
                elseif root.projects then
                    local dir = root.projects.directory
                    return roslyn_lsp.start(opt.buf, dir, roslyn_lsp.on_init_project(root.projects.files))
                end

                -- Fallback to the selected solution if we don't find anything.
                -- This makes it work kind of like vscode for the decoded files
                if vim.g.roslyn_nvim_selected_solution then
                    local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
                    return roslyn_lsp.start(opt.buf, sln_dir, roslyn_lsp.on_init_sln)
                end
            end)
        end,
    })
end

return M
