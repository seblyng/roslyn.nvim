local M = {}

---@class RoslynTestProgress
---@field testsPassed integer
---@field testsFailed integer
---@field testsSkipped integer
---@field totalTests integer

---@class RoslynRunTestsPartialResult
---@field stage string
---@field message string
---@field progress? RoslynTestProgress

---@type table<string, fun(result: RoslynRunTestsPartialResult)>
local partial_result_handlers = {}

---@type table<integer, boolean>
local clients_running_tests = {}

local test_run_count = 0

---@type integer?
local output_bufnr

---@param header string
local function show_output(header)
    if not (output_bufnr and vim.api.nvim_buf_is_valid(output_bufnr)) then
        output_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(output_bufnr, "roslyn://test-output")
    end

    vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, { header })

    if vim.fn.bufwinid(output_bufnr) == -1 then
        vim.api.nvim_open_win(output_bufnr, false, { split = "below", win = -1, height = 15 })
    end
end

---@param message string
local function append_output(message)
    if not (output_bufnr and vim.api.nvim_buf_is_valid(output_bufnr)) then
        return
    end

    vim.api.nvim_buf_set_lines(output_bufnr, -1, -1, false, vim.split(message, "\r?\n"))

    local last_line = vim.api.nvim_buf_line_count(output_bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(output_bufnr)) do
        vim.api.nvim_win_set_cursor(win, { last_line, 0 })
    end
end

---@param progress RoslynTestProgress
---@return string
local function format_summary(progress)
    return string.format(
        "Tests finished: %d passed, %d failed, %d skipped (%d total)",
        progress.testsPassed,
        progress.testsFailed,
        progress.testsSkipped,
        progress.totalTests
    )
end

---@param client vim.lsp.Client
---@param params table `RunTestsParams` as sent by the `dotnet.test.run` code lens command
function M.run(client, params)
    if clients_running_tests[client.id] then
        vim.notify("A test run is already in progress", vim.log.levels.WARN, { title = "roslyn.nvim" })
        return
    end

    -- The server builds the project from disk, so unsaved changes would not be tested
    vim.cmd("silent! wall")

    local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
    show_output(
        string.format(
            "%s tests in %s",
            params.attachDebugger and "Debugging" or "Running",
            vim.uri_to_fname(params.textDocument.uri)
        )
    )

    local record_test_signs = require("roslyn.test_signs").start_run(client, bufnr)

    test_run_count = test_run_count + 1
    local partial_result_token = "roslyn.nvim/runTests/" .. test_run_count

    ---@type RoslynTestProgress?
    local last_progress
    ---@param result RoslynRunTestsPartialResult
    local function on_partial_result(result)
        if type(result.message) == "string" and result.message ~= "" then
            append_output(result.message)
            record_test_signs(result.message)
        end
        last_progress = result.progress or last_progress
    end

    local function finish_run()
        partial_result_handlers[partial_result_token] = nil
        clients_running_tests[client.id] = nil
    end

    -- Registered before sending, because a server may respond before `request` returns
    partial_result_handlers[partial_result_token] = on_partial_result
    clients_running_tests[client.id] = true

    local sent = client:request(
        "textDocument/runTests",
        vim.tbl_extend("force", params, { partialResultToken = partial_result_token }),
        function(err, results)
            finish_run()

            for _, result in ipairs(results or {}) do
                on_partial_result(result)
            end

            if err then
                append_output(err.message)
                vim.notify("Test run failed, see roslyn://test-output", vim.log.levels.ERROR, { title = "roslyn.nvim" })
            elseif last_progress then
                local summary = format_summary(last_progress)
                append_output(summary)
                local level = last_progress.testsFailed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
                vim.notify(summary, level, { title = "roslyn.nvim" })
            else
                vim.notify("No tests found", vim.log.levels.INFO, { title = "roslyn.nvim" })
            end
        end,
        bufnr
    )
    if not sent then
        finish_run()
        append_output("The server did not accept the test run request")
        vim.notify("Test run failed, see roslyn://test-output", vim.log.levels.ERROR, { title = "roslyn.nvim" })
    end
end

---@param attach_debugger boolean
function M.run_at_cursor(attach_debugger)
    local bufnr = vim.api.nvim_get_current_buf()
    local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
    if not client then
        vim.notify("No roslyn client attached to this buffer", vim.log.levels.WARN, { title = "roslyn.nvim" })
        return
    end

    local position = vim.lsp.util.make_position_params(0, client.offset_encoding).position
    M.run(client, {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        range = { start = position, ["end"] = position },
        attachDebugger = attach_debugger,
    })
end

---@param token integer|string
---@param value RoslynRunTestsPartialResult
---@return boolean handled
function M.handle_partial_result(token, value)
    local handler = partial_result_handlers[token]
    if not handler then
        return false
    end
    handler(value)
    return true
end

return M
