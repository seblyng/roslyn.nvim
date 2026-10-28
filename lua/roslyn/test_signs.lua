local M = {}

local namespace = vim.api.nvim_create_namespace("roslyn.test_signs")

---@alias RoslynTestState "passed" | "failed" | "skipped"

---@type table<string, RoslynTestState>
local state_by_outcome = {
    passed = "passed",
    failed = "failed",
    ["timed-out"] = "failed",
    error = "failed",
    canceled = "failed",
    skipped = "skipped",
}

---@type table<RoslynTestState, integer>
local state_priority = { skipped = 1, passed = 2, failed = 3 }

---@type table<RoslynTestState, { text: string, hl_group: string }>
local sign_by_state = {
    passed = { text = "✓", hl_group = "RoslynTestPassed" },
    failed = { text = "✗", hl_group = "RoslynTestFailed" },
    skipped = { text = "○", hl_group = "RoslynTestSkipped" },
}

--- Test states shown in a buffer across runs, keyed by `<class>.<method>`, or `.<method>` when the
--- test name has no class
---@type table<integer, table<string, RoslynTestState>>
local states_by_buffer = {}

local function define_highlights()
    vim.api.nvim_set_hl(0, "RoslynTestPassed", { link = "DiagnosticOk", default = true })
    vim.api.nvim_set_hl(0, "RoslynTestFailed", { link = "DiagnosticError", default = true })
    vim.api.nvim_set_hl(0, "RoslynTestSkipped", { link = "DiagnosticWarn", default = true })
end

define_highlights()
local group = vim.api.nvim_create_augroup("roslyn.test_signs", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })
vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
        states_by_buffer[args.buf] = nil
    end,
})

---@class RoslynTestMethod
---@field class_name? string
---@field method_name string
---@field row integer

---@param symbols lsp.DocumentSymbol[]
---@param class_name? string
---@param methods RoslynTestMethod[]
local function collect_methods(symbols, class_name, methods)
    for _, symbol in ipairs(symbols) do
        local name = symbol.name:match("^[^%(]+")
        if symbol.kind == vim.lsp.protocol.SymbolKind.Method then
            table.insert(methods, { class_name = class_name, method_name = name, row = symbol.range.start.line })
        end
        local is_type = symbol.kind == vim.lsp.protocol.SymbolKind.Class
            or symbol.kind == vim.lsp.protocol.SymbolKind.Struct
        collect_methods(symbol.children or {}, is_type and name or class_name, methods)
    end
end

---@param display_name string e.g. `Namespace.Class.Method(x: 1)` or `Method`
---@return string key
local function to_test_key(display_name)
    local name_parts = vim.split(vim.trim(display_name:match("^[^%(]+") or display_name), ".", { plain = true })
    return (name_parts[#name_parts - 1] or "") .. "." .. name_parts[#name_parts]
end

--- Records result lines like `[Passed] Namespace.Class.Method` of the test output
---@param output string
---@param run_states table<string, RoslynTestState>
local function record_results(output, run_states)
    for line in vim.gsplit(output, "\r?\n") do
        local outcome, display_name = line:match("^%[([%a-]+)%] (.+)$")
        local state = outcome and state_by_outcome[outcome:lower()]
        if state then
            local key = to_test_key(display_name)
            -- A theory reports one result per case, the worst one wins
            local previous_state = run_states[key]
            if not previous_state or state_priority[state] > state_priority[previous_state] then
                run_states[key] = state
            end
        end
    end
end

---@param bufnr integer
---@param methods RoslynTestMethod[]
---@param states table<string, RoslynTestState>
local function render(bufnr, methods, states)
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    for _, method in ipairs(methods) do
        local state = states[(method.class_name or "") .. "." .. method.method_name]
            or states["." .. method.method_name]
        if state then
            local sign = sign_by_state[state]
            vim.api.nvim_buf_set_extmark(bufnr, namespace, method.row, 0, {
                sign_text = sign.text,
                sign_hl_group = sign.hl_group,
            })
        end
    end
end

--- Starts showing the results of a test run as signs next to the tests in `bufnr`.
--- Does nothing when the `test_signs` option is disabled.
---@param client vim.lsp.Client
---@param bufnr integer
---@return fun(output: string) record_output Receives every output message of the run
function M.start_run(client, bufnr)
    if not require("roslyn.config").get().test_signs then
        return function() end
    end

    ---@type table<string, RoslynTestState>
    local run_states = {}
    ---@type RoslynTestMethod[]?
    local methods

    local function show()
        if not methods or not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        states_by_buffer[bufnr] = vim.tbl_extend("force", states_by_buffer[bufnr] or {}, run_states)
        render(bufnr, methods, states_by_buffer[bufnr])
    end

    client:request("textDocument/documentSymbol", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    }, function(err, symbols)
        if err or not symbols then
            return
        end
        methods = {}
        collect_methods(symbols, nil, methods)
        show()
    end, bufnr)

    return function(output)
        record_results(output, run_states)
        show()
    end
end

return M
