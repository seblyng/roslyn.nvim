local M = {}

---@param pattern_func fun(name,path):boolean --function to check if a file is a match if not return false otherwise return true
---@param root string --root directory to where start searching
---@param deep boolean --true if you want to search recursively in subdirectories
---@return string name --name file
---@return string path --path file without name
M.find_file = function(pattern_func, root, deep)
	local name = ""
	local path = ""
	if not deep then
		for _name, type in vim.fs.dir(root) do
			if type == "file" then
				if pattern_func(_name, root) then
					name = _name
					path = root
					break
				end
			end
		end
	elseif deep then
		vim.fs.find(function(_name, _path)
			if pattern_func(_name, root) then
				name = _name
				path = _path
				return true
			end
			return false
		end, { upward = true, type = "file", limit = math.huge, path = root })
	end
	return name, path
end

return M
