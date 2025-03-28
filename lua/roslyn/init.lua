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
    if vim.fn.has("nvim-0.11") == 0 then
        return vim.notify("This plugin requires at least nvim 0.11", vim.log.levels.WARN, { title = "roslyn.nvim" })
    end

    local roslyn_config = require("roslyn.config").setup(config)

    if not vim.lsp.config.roslyn.cmd then
        return vim.notify(
            "No `cmd` for roslyn detected.\nEither install through mason or specify the path yourself through `vim.lsp.config.roslyn.cmd`",
            vim.log.levels.WARN,
            { title = "roslyn.nvim" }
        )
    end

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
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if roslyn_config.lock_target and selected_solution then
                local sln_dir = vim.fs.dirname(selected_solution)
                return roslyn_lsp.start(opt.buf, sln_dir, roslyn_lsp.on_init_sln(selected_solution))
            end

            vim.schedule(function()
                local root = utils.root(opt.buf)
                vim.b.roslyn_root = root

                local multiple, solution = utils.predict_target(root)

                if multiple then
                    vim.notify(
                        "Multiple potential target files found. Use `:Roslyn target` to select a target.",
                        vim.log.levels.INFO,
                        { title = "roslyn.nvim" }
                    )

                    -- If the user has `lock_target = true` then wait for them
                    -- to choose a target explicitly before starting the LSP.
                    if roslyn_config.lock_target then
                        return
                    end
                end

                if solution then
                    return roslyn_lsp.start(opt.buf, vim.fs.dirname(solution), roslyn_lsp.on_init_sln(solution))
                elseif root.projects then
                    local dir = root.projects.directory
                    return roslyn_lsp.start(opt.buf, dir, roslyn_lsp.on_init_project(root.projects.files))
                end

                -- Fallback to the selected solution if we don't find anything.
                -- This makes it work kind of like vscode for the decoded files
                if selected_solution then
                    local sln_dir = vim.fs.dirname(selected_solution)
                    return roslyn_lsp.start(opt.buf, sln_dir, roslyn_lsp.on_init_sln(selected_solution))
                end
            end)
        end,
    })
end

return M
