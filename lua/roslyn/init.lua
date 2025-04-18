local M = {}

---@param config? RoslynNvimConfig
function M.setup(config)
    if vim.fn.has("nvim-0.11") == 0 then
        return vim.notify("roslyn.nvim requires at least nvim 0.11", vim.log.levels.WARN, { title = "roslyn.nvim" })
    end

    local group = vim.api.nvim_create_augroup("roslyn.nvim", { clear = true })

    require("roslyn.config").setup(config)

    vim.lsp.enable("roslyn")

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "cs",
        callback = function()
            require("roslyn.commands").create_roslyn_commands()
        end,
    })

    vim.treesitter.language.register("c_sharp", "csharp")

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        group = group,
        pattern = "roslyn-source-generated://*",
        callback = function(args)
            vim.bo[args.buf].modifiable = true
            vim.bo[args.buf].swapfile = false

            -- This triggers FileType event which should fire up the lsp client if not already running
            vim.bo[args.buf].filetype = "cs"
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            assert(client, "Must have a `roslyn` client to load roslyn source generated file")

            local content
            local function handler(err, result)
                assert(not err, vim.inspect(err))
                content = result.text
                if content == nil then
                    content = ""
                end
                local normalized = string.gsub(content, "\r\n", "\n")
                local source_lines = vim.split(normalized, "\n", { plain = true })
                vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, source_lines)
                vim.b[args.buf].resultId = result.resultId
                vim.bo[args.buf].modifiable = false
            end

            local params = {
                textDocument = {
                    uri = args.match,
                },
                resultId = nil,
            }

            client:request("sourceGeneratedDocument/_roslyn_getText", params, handler, args.buf)
            -- Need to block. Otherwise logic could run that sets the cursor to a position
            -- that's still missing.
            vim.wait(1000, function()
                return content ~= nil
            end)
        end,
    })
end

return M
