-- Huge credits to mrcjkb
-- https://github.com/mrcjkb/rustaceanvim/blob/2fa45427c01ded4d3ecca72e357f8a60fd8e46d4/lua/rustaceanvim/commands/init.lua
local M = {}

local cmd_name = "Roslyn"

---@class RoslynSubcommandTable
---@field impl fun(args: string[], opts: vim.api.keyset.user_command) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's arguments

---@type RoslynSubcommandTable[]
local subcommand_tbl = {
    restart = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            local attached_buffers = vim.tbl_keys(client.attached_buffers)

            client.stop()

            local timer = vim.uv.new_timer()
            timer:start(
                500,
                100,
                vim.schedule_wrap(function()
                    if client.is_stopped() then
                        for _, buffer in ipairs(attached_buffers) do
                            vim.api.nvim_exec_autocmds("FileType", { group = "Roslyn", buffer = buffer })
                        end
                    end

                    if not timer:is_closing() then
                        timer:close()
                    end
                end)
            )
        end,
    },
    stop = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            client.stop(true)
        end,
    },
}

---@type table<integer, RoslynSubcommandTable>[]
local buffer_local_subcommand_tbl = {
    target = {},
}

---@param opts table
---@see vim.api.nvim_create_user_command
local function roslyn(opts)
    local fargs = opts.fargs
    local cmd = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local bufnr = vim.api.nvim_get_current_buf()
    local subcommand = subcommand_tbl[cmd]
    local buffer_local_subcommand = buffer_local_subcommand_tbl[cmd]
    if type(subcommand) == "table" and type(subcommand.impl) == "function" then
        subcommand.impl(args, opts)
        return
    end

    if
        type(buffer_local_subcommand) == "table"
        and type(buffer_local_subcommand[bufnr]) == "table"
        and type(buffer_local_subcommand[bufnr].impl) == "function"
    then
        buffer_local_subcommand[bufnr].impl(args, opts)
        return
    end

    vim.notify(cmd_name .. ": Unknown subcommand: " .. cmd, vim.log.levels.ERROR)
end

---@param name string
---@param bufnr integer
---@param subcmd_table RoslynSubcommandTable
function M.attach_subcommand_to_buffer(name, bufnr, subcmd_table)
    local subcmd = buffer_local_subcommand_tbl[name]
    if not subcmd then
        return vim.notify("Subcommand doesn't exist")
    end

    subcmd[bufnr] = subcmd_table
end

function M.create_roslyn_commands()
    vim.api.nvim_create_user_command(cmd_name, roslyn, {
        nargs = "+",
        range = true,
        desc = "Interacts with Roslyn",
        complete = function(arg_lead, cmdline, _)
            local bufnr = vim.api.nvim_get_current_buf()
            local commands = vim.tbl_keys(subcommand_tbl)

            local buffer_local_commands = vim.iter(vim.tbl_keys(buffer_local_subcommand_tbl))
                :filter(function(it)
                    local buffers = vim.tbl_keys(buffer_local_subcommand_tbl[it])
                    return vim.list_contains(buffers, bufnr)
                end)
                :totable()

            local all_commands = vim.list_extend(commands, buffer_local_commands)

            local subcmd, subcmd_arg_lead = cmdline:match("^" .. cmd_name .. "[!]*%s(%S+)%s(.*)$")
            if subcmd and subcmd_arg_lead and subcommand_tbl[subcmd] and subcommand_tbl[subcmd].complete then
                return subcommand_tbl[subcmd].complete(subcmd_arg_lead)
            end

            if
                subcmd
                and subcmd_arg_lead
                and buffer_local_subcommand_tbl[bufnr]
                and buffer_local_subcommand_tbl[bufnr][subcmd]
                and buffer_local_subcommand_tbl[bufnr][subcmd].complete
            then
                return buffer_local_subcommand_tbl[bufnr][subcmd].complete(subcmd_arg_lead)
            end

            if cmdline:match("^" .. cmd_name .. "[!]*%s+%w*$") then
                return vim.tbl_filter(function(command)
                    return command:find(arg_lead) ~= nil
                end, all_commands)
            end
        end,
    })
end

return M
