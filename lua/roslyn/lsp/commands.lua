---@class RoslynCodeAction
---@field title string
---@field code_action table

---@return RoslynCodeAction
local function get_code_actions(nested_code_actions)
    return vim.iter(nested_code_actions)
        :map(function(it)
            local code_action_path = it.data.CodeActionPath
            local fix_all_flavors = it.data.FixAllFlavors

            if #code_action_path == 1 then
                return {
                    title = code_action_path[1],
                    code_action = it,
                }
            end

            local title = table.concat(code_action_path, " -> ", 2)
            return {
                title = fix_all_flavors and string.format("Fix All: %s", title) or title,
                code_action = it,
            }
        end)
        :totable()
end

local function handle_fix_all_code_action(client, data)
    local flavors = data.arguments[1].FixAllFlavors
    vim.ui.select(flavors, { prompt = "Pick a fix all scope:" }, function(flavor)
        client:request("codeAction/resolveFixAll", {
            title = data.title,
            data = data.arguments[1],
            scope = flavor,
        }, function(err, response)
            if err then
                vim.notify(err.message, vim.log.levels.ERROR, { title = "roslyn.nvim" })
            end
            if response and response.edit then
                vim.lsp.util.apply_workspace_edit(response.edit, client.offset_encoding)
            end
        end)
    end)
end

--- @return [integer, integer] # (row, col) tuple
local function offset_to_position(bufnr, offset)
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n")
    local sub = text:sub(1, offset)
    local line = 0
    for _ in sub:gmatch("([^\n]*)\n?") do
        line = line + 1
    end
    local last_newline = sub:match(".*()\n")
    local col = offset - (last_newline or 0)
    return { line - 1, col }
end

return {
    ["roslyn.client.fixAllCodeAction"] = function(data, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        handle_fix_all_code_action(client, data)
    end,
    ["roslyn.client.nestedCodeAction"] = function(data, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
        local args = data.arguments[1]
        local code_actions = get_code_actions(args.NestedCodeActions)
        local titles = vim.iter(code_actions)
            :map(function(it)
                return it.title
            end)
            :totable()

        vim.ui.select(titles, { prompt = args.UniqueIdentifier }, function(selected)
            local action = vim.iter(code_actions):find(function(it)
                return it.title == selected
            end) --[[@as RoslynCodeAction]]

            if action.code_action.data.FixAllFlavors then
                handle_fix_all_code_action(client, action.code_action.command)
            else
                client:request("codeAction/resolve", {
                    title = action.code_action.title,
                    data = action.code_action.data,
                    ---@diagnostic disable-next-line: param-type-mismatch
                }, function(err, response)
                    if err then
                        vim.notify(err.message, vim.log.levels.ERROR, { title = "roslyn.nvim" })
                    end
                    if response and response.edit then
                        vim.lsp.util.apply_workspace_edit(response.edit, client.offset_encoding)
                    end
                end)
            end
        end)
    end,
    ["roslyn.client.completionComplexEdit"] = function(data)
        local doc, edit, _, new_offset = unpack(data.arguments)
        local bufnr = vim.uri_to_bufnr(doc.uri)

        if not vim.api.nvim_buf_is_loaded(bufnr) then
            vim.fn.bufload(bufnr)
        end

        local start_row = edit.range.start.line
        local start_col = edit.range.start.character
        local end_row = edit.range["end"].line
        local end_col = edit.range["end"].character

        -- It's possible to get corrupted line endings in the newText from the LSP
        -- Somehow related to typing fast
        -- Notification(int what)\r\n    {\r\n        base._Notification(what);\r\n    }\r\n\r\n\r
        local newText = edit.newText:gsub("\r\n", "\n"):gsub("\r", "")
        local lines = vim.split(newText, "\n")

        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)

        local final_line = start_row + #lines - 1
        local final_line_text = vim.api.nvim_buf_get_lines(bufnr, final_line, final_line + 1, false)[1]

        -- Handle auto-inserted parentheses
        -- "}" or ";" followed only by at least one of "(", ")", or whitespace at the end of the line
        if final_line_text:match("[};][()%s]+$") then
            local new_final_line_text = final_line_text:gsub("([};])[()%s]+$", "%1")
            lines[#lines] = new_final_line_text
            vim.api.nvim_buf_set_lines(bufnr, final_line, final_line + 1, false, { new_final_line_text })
        end

        if new_offset >= 0 then
            vim.api.nvim_win_set_cursor(0, offset_to_position(0, new_offset))
        end
    end,
}
