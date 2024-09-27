local uv = require('luv')
local M={}
M.add_element = function(path)--TODO: refactor
	uv.run("nowait") -- This is necessary to start the event loop
	local csprojPath = ""
	local nameCsproj = ""
	local sameLevelElement = ""
	local nameFile = path:match("([^/\\]+)$")
	for entry, type in vim.fs.dir(path:sub(1, - #nameFile - 1)) do
		if type == "file" then
			if entry ~= nameFile then
				sameLevelElement = entry
				break
			end
		end
	end
	vim.fs.find(function(name, _path)
		if name:match("%.csproj$") then
			csprojPath = _path
			nameCsproj = name
			return true
		end
		return false
	end, { upward = true, type = "file", limit = math.huge, path = path })
	local pathRelativeFile = ""
	if pathRelativeFile == nil then
		print("Error adding element")
		return
	end
	pathRelativeFile = path:sub(#csprojPath + 2)
	local nameRelativeFile = pathRelativeFile:match("([^/\\]+)$")
	pathRelativeFile = pathRelativeFile:gsub("/", "\\")
	sameLevelElement = pathRelativeFile:sub(1, - #nameRelativeFile - 2) .. "\\" .. sameLevelElement

	sameLevelElement = sameLevelElement:gsub("/", "\\")
	local stdin = uv.new_pipe()
	local stdout = uv.new_pipe()
	local stderr = uv.new_pipe()
	local script_path = debug.getinfo(1, "S").source:sub(2)
	local executable_path = script_path:match(".*/") .. "../../csprojManager/csprojManager.exe"
	local handle, pid = uv.spawn(
		executable_path
		, { stdio = { stdin, stdout, stderr } }, function()
			stdin:close()
			stdout:close()
			stderr:close()
		end
	)
	if not pid or not handle then
		print("error:manager not found,path:"..executable_path)
		return
	end
	--Input
	local input = {
		CsprojPath = vim.fs.joinpath(csprojPath, nameCsproj),
		WhenAddElement = sameLevelElement,
		ElementToAdd = string.format('<Compile Include="%s" />', pathRelativeFile)
	}
	local json = vim.fn.json_encode(input)
	stdin:write("add\n")
	stdin:write(json .. "\n")
	stdout:read_start(function(e, data)
		assert(not e, e)
		if data then
			vim.schedule(function()
				print(data)
				require("roslyn.slnutils").did_change_watched_file(path)
			end)
		end
	end)
	stderr:read_start(function(e, data)
		assert(not e, e)
		if data then
			print(data)
		end
	end)
end
M.remove_element=function()--TODO

end
return M
