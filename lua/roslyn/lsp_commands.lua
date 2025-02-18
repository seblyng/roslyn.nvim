local M = {}

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
        -- TODO: Change this to `client:request` when minimal version is `0.11`
        client.request("codeAction/resolveFixAll", {
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

---@param client vim.lsp.Client
function M.fix_all_code_action(client)
    vim.lsp.commands["roslyn.client.fixAllCodeAction"] = function(data)
        handle_fix_all_code_action(client, data)
    end
end

---@param client vim.lsp.Client
function M.nested_code_action(client)
    vim.lsp.commands["roslyn.client.nestedCodeAction"] = function(data)
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
                -- TODO: Change this to `client:request` when minimal version is `0.11`
                ---@diagnostic disable-next-line: param-type-mismatch
                client.request("codeAction/resolve", {
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
    end
end

function M.completion_complex_edit()
    local function best_cursor_pos(lines, start_row, start_col)
        local target_i, col

        for i = #lines, 1, -1 do
            local line = lines[i]
            for j = #line, 1, -1 do
                if not line:sub(j, j):match("[%s(){}]") then
                    target_i = i + 1
                    col = j
                    break
                end
            end
            if target_i then
                break
            end
        end

        -- Fallback position if somehow not found
        if not target_i then
            target_i = #lines
            col = #lines[target_i] or 0
        end

        local row = start_row + target_i - 1
        if target_i == 1 then
            col = start_col + col
        end

        return { row, col }
    end

    vim.lsp.commands["roslyn.client.completionComplexEdit"] = function(data, _)
        local arguments = data.arguments
        local uri = arguments[1].uri
        local edit = arguments[2]
        local bufnr = vim.uri_to_bufnr(uri)

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

        vim.api.nvim_win_set_cursor(0, best_cursor_pos(lines, start_row, start_col))
    end
end

return M
