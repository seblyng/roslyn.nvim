local helpers = require("test.utils.helpers")

helpers.env()

describe("source generated buffers", function()
    before_each(function()
        helpers.clear()
        helpers.exec_lua("package.path = ...", package.path)
    end)

    it("loads with fallback roslyn client and stays unmodified", function()
        local result = helpers.exec_lua(function()
            local cwd = vim.uv.cwd()
            local plugin_path = vim.fs.joinpath(cwd, "plugin", "roslyn.lua")

            vim.g.loaded_roslyn_plugin = nil
            local original_enable = vim.lsp.enable
            vim.lsp.enable = function() end
            dofile(plugin_path)
            vim.lsp.enable = original_enable

            local buf_lookup_calls = 0
            local global_lookup_calls = 0
            local request_method

            local fake_client = {
                request = function(_, method, _, callback)
                    request_method = method
                    callback(nil, {
                        text = "line one\r\nline two",
                        resultId = "1",
                    })
                end,
            }

            local original_get_clients = vim.lsp.get_clients
            vim.lsp.get_clients = function(filter)
                if filter and filter.name == "roslyn" and filter.bufnr ~= nil then
                    buf_lookup_calls = buf_lookup_calls + 1
                    return {}
                end

                if filter and filter.name == "roslyn" then
                    global_lookup_calls = global_lookup_calls + 1
                    return { fake_client }
                end

                return {}
            end

            local ok, err = pcall(function()
                vim.cmd.edit("roslyn-source-generated://test/generated.cs")
            end)

            local bufnr = vim.api.nvim_get_current_buf()
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local modified = vim.bo[bufnr].modified

            vim.lsp.get_clients = original_get_clients

            return {
                ok = ok,
                err = err,
                buf_lookup_calls = buf_lookup_calls,
                global_lookup_calls = global_lookup_calls,
                request_method = request_method,
                lines = lines,
                modified = modified,
            }
        end)

        assert.is_true(result.ok)
        assert.are_equal(nil, result.err)
        assert.are_equal("sourceGeneratedDocument/_roslyn_getText", result.request_method)
        assert.is_true(result.buf_lookup_calls > 0)
        assert.is_true(result.global_lookup_calls > 0)
        assert.are_same({ "line one", "line two" }, result.lines)
        assert.is_false(result.modified)
    end)

    it("refresh keeps source generated buffer unmodified", function()
        local result = helpers.exec_lua(function()
            local bufnr = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_name(bufnr, "roslyn-source-generated://test/generated.cs")

            vim.bo[bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "old" })
            vim.bo[bufnr].modified = false
            vim.bo[bufnr].modifiable = false
            vim.b[bufnr].resultId = "old-result"

            local original_get_client_by_id = vim.lsp.get_client_by_id
            vim.lsp.get_client_by_id = function()
                return {
                    request = function(_, _, _, callback)
                        callback(nil, {
                            text = "new\r\ncontent",
                            resultId = "new-result",
                        })
                    end,
                }
            end

            local handler = require("roslyn.lsp.handlers")["workspace/refreshSourceGeneratedDocument"]
            handler(nil, nil, { client_id = 1 })

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local modified = vim.bo[bufnr].modified

            vim.lsp.get_client_by_id = original_get_client_by_id
            vim.api.nvim_buf_delete(bufnr, { force = true })

            return {
                lines = lines,
                modified = modified,
            }
        end)

        assert.are_same({ "new", "content" }, result.lines)
        assert.is_false(result.modified)
    end)
end)
