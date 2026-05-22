local function get_default_cmd()
    local resolved = require("roslyn.utils").get_roslyn_lsp_path()
    local exe = resolved and resolved.path or "Microsoft.CodeAnalysis.LanguageServer"

    local cmd = {
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.log.get_filename()),
        "--stdio",
    }

    local roslyn_extensions = require("roslyn.config").get().extensions or {}
    for ext_name, extension in pairs(roslyn_extensions) do
        if extension.enabled then
            local resolved_config = type(extension.config) == "function" and extension.config() or extension.config

            local resolved_path = type(resolved_config.path) == "function" and resolved_config.path()
                or resolved_config.path

            if resolved_path == nil then
                vim.notify(
                    string.format("Extension '%s' is enabled but no path was provided. Skipping...", ext_name),
                    vim.log.levels.WARN,
                    { title = "roslyn.nvim" }
                )
            else
                vim.list_extend(cmd, { "--extension=" .. resolved_path })
            end

            if resolved_config.args then
                local resolved_args = type(resolved_config.args) == "function" and resolved_config.args()
                    or resolved_config.args
                vim.list_extend(cmd, resolved_args)
            end
        end
    end

    return cmd
end

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs", "razor" },
    cmd = function(dispatchers, config)
        return vim.lsp.rpc.start(get_default_cmd(), dispatchers, {
            cwd = config.cmd_cwd,
            env = config.cmd_env,
            detached = config.detached,
        })
    end,
    cmd_env = {
        Configuration = vim.env.Configuration or "Debug",
        -- Fixes LSP navigation in decompiled files for systems with symlinked TMPDIR (macOS)
        TMPDIR = vim.env.TMPDIR and vim.fn.resolve(vim.env.TMPDIR) or nil,
    },
    settings = {
        razor = {
            language_server = {
                cohosting_enabled = true,
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        local target = require("roslyn.target")
        local decision = target.resolve(bufnr)
        target.notify_if_needed(decision)
        target.remember(decision)
        on_dir(decision.root_dir)
    end,
    on_init = {
        function(client)
            -- Although roslyn supports prepareRename, cohosted razor doesnt. So we need to disable it
            client.server_capabilities.renameProvider = true

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
            require("roslyn.store").set(client_id, nil)
            vim.schedule(function()
                require("roslyn.roslyn_emitter").emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
    commands = require("roslyn.lsp.commands"),
    handlers = require("roslyn.lsp.handlers"),
}
