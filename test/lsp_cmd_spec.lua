local helpers = require("test.utils.helpers")

local function cmd_contains(cmd, value)
    for _, entry in ipairs(cmd) do
        if entry == value then
            return true
        end
    end
    return false
end

local function cmd_has_prefix(cmd, prefix)
    for _, entry in ipairs(cmd) do
        if type(entry) == "string" and vim.startswith(entry, prefix) then
            return true
        end
    end
    return false
end

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

    it("adds extension path and args when provided", function()
        local cmd = helpers.exec_lua(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = {
                            path = "/tmp/roslyn-test-extension.dll",
                            args = { "--foo=bar", "--baz" },
                        },
                    },
                },
            })

            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))
            return lsp_config.cmd
        end)

        assert.is_true(cmd_contains(cmd, "--extension=/tmp/roslyn-test-extension.dll"))
        assert.is_true(cmd_contains(cmd, "--foo=bar"))
        assert.is_true(cmd_contains(cmd, "--baz"))
    end)

    it("skips extension when no path is provided", function()
        local cmd = helpers.exec_lua(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = { path = nil },
                    },
                },
            })

            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))
            return lsp_config.cmd
        end)

        assert.is_false(cmd_has_prefix(cmd, "--extension="))
    end)

    it("supports extension config as function", function()
        local cmd = helpers.exec_lua(function()
            require("roslyn.config").setup({
                extensions = {
                    razor = { enabled = false },
                    testext = {
                        enabled = true,
                        config = function()
                            return {
                                path = "/tmp/roslyn-test-extension-fn.dll",
                                args = { "--alpha", "--beta=1" },
                            }
                        end,
                    },
                },
            })

            local cwd = vim.uv.cwd()
            local lsp_config = dofile(vim.fs.joinpath(cwd, "lsp", "roslyn.lua"))
            return lsp_config.cmd
        end)

        assert.is_true(cmd_contains(cmd, "--extension=/tmp/roslyn-test-extension-fn.dll"))
        assert.is_true(cmd_contains(cmd, "--alpha"))
        assert.is_true(cmd_contains(cmd, "--beta=1"))
    end)
end)
