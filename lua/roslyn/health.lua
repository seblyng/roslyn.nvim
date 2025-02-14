M = {}
local name = "roslyn"
local h = vim.health
local config = require("roslyn.config").get()
local sln_api = require("roslyn.sln.api")
local check_config = function()
	h.start("configuration checks")
	if type(config) ~= "table" then
		h.error(
			"config is not a table " .. vim.inspect(config),
			[=[
{
    "seblyng/roslyn.nvim",
    ft = "cs",
    opts = {
        -- your configuration comes here; leave empty for default settings
    }
}
]=]
		)
		return false
	end

	for i, pm in ipairs(config) do
		if pm == nil then
			h.error("config is not correct on index[" .. i .. "]")
			return false
		end
	end
	h.ok(name .. " configuration setup correct.")
	return true
end

---@alias roslyn_client vim.lsp.Client
local check_lsp = function()
	h.start("lsp setup checks")
	local roslyn_client = vim.lsp.get_clients({ name = name })[1]
	if roslyn_client == nil then
		h.error("Lsp client not found (" .. name .. ")")
		return false
	end

	if roslyn_client.root_dir ~= nil then
		h.ok("root directory " .. roslyn_client.root_dir)
	end
	-- h.info("client info: " .. vim.inspect(roslyn_client))

	local sln = vim.g.roslyn_nvim_selected_solution
	if sln == nil or string.len(sln) < 1 then
		h.warn("solution file not found")
	else
		h.ok("Initialized solution: " .. sln)
	end

	h.ok(name .. " lsp running correctly.")
	return true
end

M.check = function()
	check_config()
	check_lsp()
end

return M
