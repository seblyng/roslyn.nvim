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

---@type boolean
local roslyn_version_verified = false

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

            if not roslyn_version_verified then
                -- TODO: Remove this in a few months or so
                -- vim.system will fail with required args not provided if `--stdio` exists as an argument
                -- to the version installed, so this should be safe
                local cmd = vim.list_extend(vim.deepcopy(roslyn_config.exe), { "--stdio" })
                local stderr = vim.system(cmd):wait().stderr
                if stderr and string.find(stderr, "Unrecognized command or argument '--stdio'.", 0, true) then
                    return vim.notify(
                        "The roslyn language server needs to be updated. Refer to the README for installation steps",
                        vim.log.levels.INFO,
                        { title = "roslyn.nvim" }
                    )
                end
                roslyn_version_verified = true
            end

            -- Lock the target and always start with the currently selected solution
            if roslyn_config.lock_target and vim.g.roslyn_nvim_selected_solution then
                local sln_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
                return roslyn_lsp.start(opt.buf, sln_dir, roslyn_lsp.on_init_sln)
            end

            utils.select_solution()

            --[[ vim.schedule(function()
                local root = utils.root(opt.buf)
                vim.b.roslyn_root = root

                local multiple, solution = utils.predict_target(root)

                if multiple then
                    -- If the user has `lock_target = true` then wait for them
                    -- to choose a target explicitly before starting the LSP.
                    --
                    -- For `lock_target = false`, being asked to choose a target
                    -- on every opened file would be annoying, so fall back to
                    -- default handling.
                    if roslyn_config.lock_target then
                        vim.notify(
                            "Multiple potential target files found. Use `:Roslyn target` to select a target.",
                            vim.log.levels.INFO,
                            { title = "roslyn.nvim" }
                        )
                        return
                    end

                    vim.notify(
                        "Multiple potential target files found. Use `:Roslyn target` to change the target for the current buffer.",
                        vim.log.levels.INFO,
                        { title = "roslyn.nvim" }
                    )
                end

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
            end) ]]
        end,
    })
end

return M
