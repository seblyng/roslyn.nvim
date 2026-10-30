local M = {}

---@class RoslynRunTestsPartialResult
---@field stage string
---@field message string

---@type table<string, fun(message: string)>
local output_handlers = {}

---@param client vim.lsp.Client
---@param params table `RunTestsParams` as sent by the `dotnet.test.run` code lens command
function M.run(client, params)
    local token = "roslyn://tests/" .. client.id
    local bufnr = vim.fn.bufnr(token)
    if bufnr == -1 then
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(bufnr, token)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    if vim.fn.bufwinid(bufnr) == -1 then
        vim.api.nvim_open_win(bufnr, false, { split = "below", height = 15 })
    end

    local function append(message)
        if message and message ~= "" and vim.api.nvim_buf_is_valid(bufnr) then
            local last = vim.api.nvim_buf_line_count(bufnr) - 1
            local line = vim.api.nvim_buf_get_lines(bufnr, last, last + 1, false)[1]
            vim.api.nvim_buf_set_text(bufnr, last, #line, last, #line, vim.split(message .. "\n", "\r?\n"))
            local last_line = vim.api.nvim_buf_line_count(bufnr)
            for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
                vim.api.nvim_win_set_cursor(win, { last_line, 0 })
            end
        end
    end

    output_handlers[token] = append
    params = vim.tbl_extend("force", params, { partialResultToken = token })

    ---@diagnostic disable-next-line: param-type-mismatch
    local sent = client:request("textDocument/runTests", params, function(err, results)
        output_handlers[token] = nil
        for _, result in ipairs(results or {}) do
            append(result.message)
        end

        if err then
            append(err.message)
        end
    end, vim.uri_to_bufnr(params.textDocument.uri))

    if not sent then
        output_handlers[token] = nil
        append("The server did not accept the test run request")
    end
end

---@param token integer|string
---@param value RoslynRunTestsPartialResult
---@return boolean handled
function M.handle_partial_result(token, value)
    local append = output_handlers[token]
    if not append then
        return false
    end

    append(value.message)

    return true
end

return M
