local M = {}

local namespace = vim.api.nvim_create_namespace("roslyn.auto_insert")

---@param client vim.lsp.Client
---@param bufnr integer
---@param response table
local function apply_auto_insert_edit(client, bufnr, response)
    local edit = response._vs_textEdit
    local new_text = edit.newText

    local text_before_caret
    local caret_marker = response._vs_textEditFormat == vim.lsp.protocol.InsertTextFormat.Snippet
        and new_text:find("$0", 1, true)
    if caret_marker then
        text_before_caret = new_text:sub(1, caret_marker - 1)
        new_text = text_before_caret .. new_text:sub(caret_marker + 2)
    end

    vim.lsp.util.apply_text_edits({ { range = edit.range, newText = new_text } }, bufnr, client.offset_encoding)

    if text_before_caret and vim.api.nvim_get_current_buf() == bufnr then
        local start_row = edit.range.start.line
        local start_line_text = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1]
        local start_col = vim.str_byteindex(start_line_text, client.offset_encoding, edit.range.start.character, false)
        local lines_before_caret = vim.split(text_before_caret, "\r?\n")
        local caret_row = start_row + #lines_before_caret - 1
        local caret_col = #lines_before_caret == 1 and start_col + #lines_before_caret[1]
            or #lines_before_caret[#lines_before_caret]
        vim.api.nvim_win_set_cursor(0, { caret_row + 1, caret_col })
    end

    if response.command then
        client:exec_cmd(response.command, { bufnr = bufnr })
    end
end

local function only_whitespace_before_cursor()
    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
    return vim.api.nvim_get_current_line():sub(1, cursor_col):match("^%s*$") ~= nil
end

---@param client vim.lsp.Client
---@param bufnr integer
---@param trigger_character string
local function request_auto_insert(client, bufnr, trigger_character)
    -- Failsafe as nvim may already have continued a comment on the new line (`formatoptions+=r`)
    if trigger_character == "\n" and not only_whitespace_before_cursor() then
        return
    end

    local params = {
        _vs_textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        _vs_position = vim.lsp.util.make_position_params(0, client.offset_encoding).position,
        _vs_ch = trigger_character,
        _vs_options = vim.lsp.util.make_formatting_params().options,
    }

    ---@diagnostic disable-next-line: param-type-mismatch
    client:request("textDocument/_vs_onAutoInsert", params, function(err, response, ctx)
        if err or not response or vim.lsp.util.buf_versions[bufnr] ~= ctx.version then
            return
        end
        apply_auto_insert_edit(client, bufnr, response)
    end, bufnr)
end

---@param typed string
local function on_key(_, typed)
    local mode = vim.api.nvim_get_mode()
    if mode.blocking or mode.mode:sub(1, 1) ~= "i" then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    if vim.bo[bufnr].filetype ~= "cs" then
        return
    end

    local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
    local trigger_characters = client
        and vim.tbl_get(client.server_capabilities, "_vs_onAutoInsertProvider", "_vs_triggerCharacters")
    local trigger_character = typed == "\r" and "\n" or typed
    if not trigger_characters or not vim.list_contains(trigger_characters, trigger_character) then
        return
    end

    vim.schedule(function()
        request_auto_insert(client, bufnr, trigger_character)
    end)
end

function M.enable()
    vim.on_key(on_key, namespace)
end

return M
