local sysname = vim.uv.os_uname().sysname:lower()
local iswin = not not (sysname:find("windows") or sysname:find("mingw"))

-- Default to roslyn presumably installed by mason if found.
-- Fallback to the same default as `nvim-lspconfig`
local function get_default_cmd()
    local roslyn_bin = iswin and "roslyn.cmd" or "roslyn"

    -- Fallback in case mason is lazy loaded or MASON env var is just not set
    local expanded_mason = vim.fn.expand("$MASON")
    local mason = expanded_mason == "$MASON" and vim.fs.joinpath(vim.fn.stdpath("data"), "mason") or expanded_mason

    local mason_bin = vim.fs.joinpath(mason, "bin", roslyn_bin)

    local exe = vim.fn.executable(mason_bin) == 1 and mason_bin
        or vim.fn.executable(roslyn_bin) == 1 and roslyn_bin
        or "Microsoft.CodeAnalysis.LanguageServer"

    local cmd = {
        exe,
        "--logLevel=Information",
        "--extensionLogDirectory=" .. vim.fs.dirname(vim.lsp.log.get_filename()),
        "--stdio",
    }

    local function find_razor_extension_path()
        local mason_packages = vim.fs.joinpath(mason, "packages")

        local stable_path = vim.fs.joinpath(mason_packages, "roslyn", "libexec", ".razorExtension")
        if vim.fn.isdirectory(stable_path) == 1 then
            return stable_path
        end

        -- TODO: Once the .razorExtension moves to the stable roslyn package, remove this
        local unstable_path = vim.fs.joinpath(mason_packages, "roslyn-unstable", "libexec", ".razorExtension")
        if vim.fn.isdirectory(unstable_path) == 1 then
            return unstable_path
        end

        return nil
    end

    local razor_extension_path = find_razor_extension_path()
    if razor_extension_path ~= nil then
        cmd = vim.list_extend(cmd, {
            "--razorSourceGenerator="
                .. vim.fs.joinpath(razor_extension_path, "Microsoft.CodeAnalysis.Razor.Compiler.dll"),
            "--razorDesignTimePath="
                .. vim.fs.joinpath(razor_extension_path, "Targets", "Microsoft.NET.Sdk.Razor.DesignTime.targets"),
            "--extension",
            vim.fs.joinpath(razor_extension_path, "Microsoft.VisualStudioCode.RazorExtension.dll"),
        })
    end
    return cmd
end

---@type vim.lsp.Config
return {
    name = "roslyn",
    filetypes = { "cs", "razor" },
    cmd = get_default_cmd(),
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
    settings = {
        razor = {
            language_server = {
                cohosting_enabled = true,
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        if require("roslyn.config").get().lock_target and vim.g.roslyn_nvim_selected_solution then
            local root_dir = vim.fs.dirname(vim.g.roslyn_nvim_selected_solution)
            on_dir(root_dir)
            return
        end

        -- For source-generated files, use the root_dir from the existing client
        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        if buf_name:match("^roslyn%-source%-generated://") then
            local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if existing_client and existing_client.config.root_dir then
                on_dir(existing_client.config.root_dir)
                return
            end
        end

        local root_dir = require("roslyn.sln.utils").root_dir(bufnr)
        on_dir(root_dir)
    end,
    on_init = {
        function(client)
            -- Although roslyn supports prepareRename, cohosted razor doesnt. So we need to disable it
            client.server_capabilities.renameProvider = true

            -- Disable semantictokens for > nvim 0.12 as `/full` requests aren't support for razor files
            -- TODO: Remove when 0.12 is stable
            if vim.fn.has("nvim-0.12") == 0 then
                vim.api.nvim_create_autocmd("LspAttach", {
                    callback = function(args)
                        if vim.api.nvim_get_option_value("filetype", { buf = args.buf }) == "razor" then
                            if args.data.client_id == client.id then
                                client.server_capabilities.semanticTokensProvider = nil
                            end
                        end
                    end,
                })
            end

            if not client.config.root_dir then
                return
            end
            require("roslyn.log").log(string.format("lsp on_init root_dir: %s", client.config.root_dir))

            local utils = require("roslyn.sln.utils")
            local on_init = require("roslyn.lsp.on_init")

            local config = require("roslyn.config").get()
            local selected_solution = vim.g.roslyn_nvim_selected_solution
            if config.lock_target and selected_solution then
                return on_init.sln(client, selected_solution)
            end

            local files = utils.find_files_with_extensions(client.config.root_dir, { ".sln", ".slnx", ".slnf" })

            local bufnr = vim.api.nvim_get_current_buf()
            local solution = utils.predict_target(bufnr, files)
            if solution then
                return on_init.sln(client, solution)
            end

            local csproj = utils.find_files_with_extensions(client.config.root_dir, { ".csproj" })
            if #csproj > 0 then
                return on_init.project(client, csproj)
            end

            if selected_solution then
                return on_init.sln(client, selected_solution)
            end
        end,
    },
    on_exit = {
        function()
            vim.g.roslyn_nvim_selected_solution = nil
            vim.schedule(function()
                require("roslyn.roslyn_emitter").emit("stopped")
                vim.notify("Roslyn server stopped", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end)
        end,
    },
    commands = require("roslyn.lsp.commands"),
    handlers = require("roslyn.lsp.handlers"),
}
