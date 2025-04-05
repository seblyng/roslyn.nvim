local roslyn_emitter = require("roslyn.roslyn_emitter")
-- Huge credits to mrcjkb
-- https://github.com/mrcjkb/rustaceanvim/blob/2fa45427c01ded4d3ecca72e357f8a60fd8e46d4/lua/rustaceanvim/commands/init.lua
local M = {}

local cmd_name = "Roslyn"

---@class RoslynSubcommandTable
---@field impl fun(args: string[], opts: vim.api.keyset.user_command) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's arguments

---@type RoslynSubcommandTable[]
local subcommand_tbl = {
    log = {
        impl = function()
            local log = require("roslyn.log")
            vim.cmd(string.format("tabnew %s", log.__log_file_path))
        end,
    },
    restart = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            local attached_buffers = vim.tbl_keys(client.attached_buffers)

            ---@type function | nil
            local remove_listener = nil

            local function restart_lsp()
                for _, buffer in ipairs(attached_buffers) do
                    if vim.api.nvim_buf_is_valid(buffer) then
                        vim.api.nvim_exec_autocmds("FileType", { group = "Roslyn", buffer = buffer })
                    end
                end
                if remove_listener then
                    remove_listener()
                end
            end

            remove_listener = roslyn_emitter:on("stopped", restart_lsp)

            local force_stop = vim.loop.os_uname().sysname == "Windows_NT"
            client:stop(force_stop)
        end,
    },
    stop = {
        impl = function()
            local client = vim.lsp.get_clients({ name = "roslyn" })[1]
            if not client then
                return
            end

            client:stop(true)
        end,
    },
    target = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local root = vim.b.roslyn_root or require("roslyn.sln.utils").root(bufnr)

            local roslyn_lsp = require("roslyn.lsp")

            local targets = vim.iter({ root.solutions, root.solution_filters }):flatten():totable()
            vim.ui.select(targets or {}, { prompt = "Select target solution: " }, function(file)
                if not file then
                    return
                end

                vim.lsp.stop_client(vim.lsp.get_clients({ name = "roslyn" }), true)
                local sln_dir = vim.fs.dirname(file)
                roslyn_lsp.start(bufnr, assert(sln_dir), roslyn_lsp.on_init_sln(file))
            end)
        end,
    },
}

---@param opts table
---@see vim.api.nvim_create_user_command
local function roslyn(opts)
    local fargs = opts.fargs
    local cmd = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[cmd]
    if type(subcommand) == "table" and type(subcommand.impl) == "function" then
        subcommand.impl(args, opts)
        return
    end

    vim.notify(cmd_name .. ": Unknown subcommand: " .. cmd, vim.log.levels.ERROR, { title = "roslyn.nvim" })
end

function M.create_roslyn_commands()
    vim.api.nvim_create_user_command(cmd_name, roslyn, {
        nargs = "+",
        range = true,
        desc = "Interacts with Roslyn",
        complete = function(arg_lead, cmdline, _)
            local all_commands = vim.tbl_keys(subcommand_tbl)

            local subcmd, subcmd_arg_lead = cmdline:match("^" .. cmd_name .. "[!]*%s(%S+)%s(.*)$")
            if subcmd and subcmd_arg_lead and subcommand_tbl[subcmd] and subcommand_tbl[subcmd].complete then
                return subcommand_tbl[subcmd].complete(subcmd_arg_lead)
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
