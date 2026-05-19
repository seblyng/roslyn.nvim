---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs", "razor" },
    cmd = { require("roslyn.utils").get_roslyn_lsp_path(), "--stdio" },
    cmd_env = {
        Configuration = vim.env.Configuration or "Debug",
        -- Fixes LSP navigation in decompiled files for systems with symlinked TMPDIR (macOS)
        TMPDIR = vim.env.TMPDIR and vim.fn.resolve(vim.env.TMPDIR) or nil,
    },
    root_dir = function(bufnr, on_dir)
        local target = require("roslyn.target")
        local decision = target.resolve(bufnr)
        target.notify_if_needed(decision)
        target.remember(decision)
        on_dir(decision.root_dir)
    end,
    on_init = {
        --- @param client vim.lsp.Client
        function(client)
            if not client.config.root_dir then
                return
            end
            require("roslyn.log").log(string.format("lsp on_init root_dir: %s", client.config.root_dir))

            local on_init = require("roslyn.lsp.on_init")
            local target = require("roslyn.target")

            local decision = target.consume(client.config.root_dir) or target.resolve(vim.api.nvim_get_current_buf())
            if decision.kind == "solution" then
                return on_init.sln(client, decision.target)
            elseif decision.kind == "project" then
                return on_init.project(client, decision.projects)
            end
        end,
    },
    on_exit = {
        function(_, _, client_id)
            require("roslyn.store").clear_client_target(client_id)
            vim.schedule(function()
                require("roslyn.roslyn_emitter").emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
    commands = require("roslyn.lsp.commands"),
    handlers = require("roslyn.lsp.handlers"),
}
