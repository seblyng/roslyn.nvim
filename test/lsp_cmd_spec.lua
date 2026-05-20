local helpers = require("test.utils.helpers")

helpers.env()

describe("lsp cmd", function()
    after_each(function()
        helpers.exec_lua(function()
            package.loaded["roslyn.config"] = nil
            require("roslyn.config")
        end)
    end)

    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
    end)

    it("shows deprecation notice when extensions are configured", function()
        local deprecate = helpers.exec_lua(function()
            require("roslyn.config").setup({
                extensions = {
                    testext = {
                        enabled = true,
                        config = {
                            path = "/tmp/roslyn-test-extension.dll",
                            args = { "--foo=bar", "--baz" },
                        },
                    },
                },
            })

            local captured_deprecate
            vim.deprecate = function(...)
                captured_deprecate = { ... }
            end

            vim.lsp.rpc = vim.lsp.rpc or {}
            vim.lsp.rpc.start = function()
                return {}
            end

            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))
            lsp_config.cmd({}, { cmd_cwd = nil, cmd_env = nil, detached = nil })
            return captured_deprecate
        end)

        assert.are.same({
            "roslyn.nvim extensions",
            'vim.lsp.config("roslyn", { cmd = ... })',
            "soon",
            "roslyn.nvim",
        }, deprecate)
    end)
end)
