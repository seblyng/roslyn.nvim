-- Huge credits to mrcjkb
-- https://github.com/mrcjkb/rustaceanvim/blob/2fa45427c01ded4d3ecca72e357f8a60fd8e46d4/lua/rustaceanvim/commands/init.lua
local M = {}

local roslyn_cmd_name = "Roslyn"

---@class command_tbl
---@field impl fun(args: string[], opts: vim.api.keyset.user_command) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's arguments

---@type command_tbl[]
local roslyn_command_tbl = {
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
                            vim.api.nvim_exec_autocmds("BufEnter", { group = "Roslyn", buffer = buffer })
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

---@param command_tbl command_tbl
---@param opts table
---@see vim.api.nvim_create_user_command
local function run_command(command_tbl, cmd_name, opts)
    local fargs = opts.fargs
    local cmd = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local command = command_tbl[cmd]
    if type(command) ~= "table" or type(command.impl) ~= "function" then
        vim.notify(cmd_name .. ": Unknown subcommand: " .. cmd, vim.log.levels.ERROR)
        return
    end
    command.impl(args, opts)
end

---@param opts table
---@see vim.api.nvim_create_user_command
local function roslyn(opts)
    run_command(roslyn_command_tbl, roslyn_cmd_name, opts)
end

function M.create_roslyn_commands()
    vim.api.nvim_create_user_command(roslyn_cmd_name, roslyn, {
        nargs = "+",
        range = true,
        desc = "Interacts with Roslyn",
        complete = function(arg_lead, cmdline, _)
            local commands = vim.tbl_keys(roslyn_command_tbl)
            local subcmd, subcmd_arg_lead = cmdline:match("^" .. roslyn_cmd_name .. "[!]*%s(%S+)%s(.*)$")
            if subcmd and subcmd_arg_lead and roslyn_command_tbl[subcmd] and roslyn_command_tbl[subcmd].complete then
                return roslyn_command_tbl[subcmd].complete(subcmd_arg_lead)
            end
            if cmdline:match("^" .. roslyn_cmd_name .. "[!]*%s+%w*$") then
                return vim.tbl_filter(function(command)
                    return command:find(arg_lead) ~= nil
                end, commands)
            end
        end,
    })
end

return M
