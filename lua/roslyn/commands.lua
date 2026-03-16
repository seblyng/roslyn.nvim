local roslyn_emitter = require("roslyn.roslyn_emitter")
-- Huge credits to mrcjkb
-- https://github.com/mrcjkb/rustaceanvim/blob/2fa45427c01ded4d3ecca72e357f8a60fd8e46d4/lua/rustaceanvim/commands/init.lua
local M = {}

local cmd_name = "Roslyn"

---@param fun function
local on_stopped = function(fun)
    ---@type function | nil
    local remove_listener = nil

    local function _fun()
        fun()
        if remove_listener then
            remove_listener()
        end
    end

    remove_listener = roslyn_emitter.on("stopped", _fun)
end

---@class RoslynSubcommandTable
---@field impl fun(args: string[], opts: vim.api.keyset.user_command) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Command completions callback, taking the lead of the subcommand's arguments

---@type RoslynSubcommandTable[]
local subcommand_tbl = {
    restart = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
            if not client then
                return
            end

            on_stopped(function()
                vim.lsp.enable("roslyn")
            end)

            local force_stop = vim.uv.os_uname().sysname == "Windows_NT"
            client:stop(force_stop)
        end,
    },
    stop = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
            if not client then
                return
            end

            local force_stop = vim.uv.os_uname().sysname == "Windows_NT"
            client:stop(force_stop)
        end,
    },
    target = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local utils = require("roslyn.sln.utils")
            local broad_search = require("roslyn.config").get().broad_search
            local targets = broad_search and utils.find_solutions_broad(bufnr) or utils.find_solutions(bufnr)
            vim.ui.select(targets or {}, {
                prompt = "Select target solution: ",
                format_item = function(item)
                    return vim.fn.fnamemodify(item, ":.")
                end,
            }, function(file)
                if not file then
                    return
                end

                local config = vim.tbl_deep_extend("force", vim.lsp.config["roslyn"], {
                    root_dir = vim.fs.dirname(file),
                    on_init = function(client)
                        require("roslyn.lsp.on_init").sln(client, file)
                    end,
                })

                local client = vim.lsp.get_clients({ name = "roslyn", bufnr = bufnr })[1]
                if not client then
                    vim.lsp.start(config, { bufnr = bufnr })
                    return
                end

                -- Start it in the buffer we got when running the command
                -- For some reason, it is a bit problematic to stop it, and it
                -- requires the user to do some action like triggering some LSP
                -- functionality (e.g. hover) before things actually happen
                on_stopped(function()
                    vim.lsp.start(config, { bufnr = bufnr })
                end)

                local force_stop = vim.uv.os_uname().sysname == "Windows_NT"
                client:stop(force_stop)
            end)
        end,
    },
    start = {
        impl = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local utils = require("roslyn.sln.utils")
            local broad_search = require("roslyn.config").get().broad_search
            local solutions = broad_search and utils.find_solutions_broad(bufnr) or utils.find_solutions(bufnr)

            -- If we have more than one solution, immediately ask to pick one
            if #solutions > 1 then
                vim.ui.select(solutions or {}, { prompt = "Select target solution: " }, function(file)
                    if not file then
                        return
                    end

                    local config = vim.tbl_deep_extend("force", vim.lsp.config["roslyn"], {
                        root_dir = vim.fs.dirname(file),
                        on_init = function(client)
                            require("roslyn.lsp.on_init").sln(client, file)
                        end,
                    })
                    vim.lsp.start(config, { bufnr = bufnr })
                end)
                return
            end

            vim.lsp.enable("roslyn")
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
