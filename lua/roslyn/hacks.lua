local M = {}

---@param handler function
---@param filewatching boolean
function M.with_filtered_watchers(handler, filewatching)
    return function(err, res, ctx, config)
        for _, reg in ipairs(res.registrations) do
            if reg.method == vim.lsp.protocol.Methods.workspace_didChangeWatchedFiles then
                local watchers = vim.tbl_filter(function(watcher)
                    if type(watcher.globPattern) == "table" then
                        local base_uri = nil ---@type string?
                        if type(watcher.globPattern.baseUri) == "string" then
                            base_uri = watcher.globPattern.baseUri
                            -- remove trailing slash if present
                            if base_uri:sub(-1) == "/" then
                                watcher.globPattern.baseUri = base_uri:sub(1, -2)
                            end
                        elseif type(watcher.globPattern.baseUri) == "table" then
                            base_uri = watcher.globPattern.baseUri.uri
                            -- remove trailing slash if present
                            if base_uri:sub(-1) == "/" then
                                watcher.globPattern.baseUri.uri = base_uri:sub(1, -2)
                            end
                        end

                        if base_uri ~= nil then
                            local base_dir = vim.uri_to_fname(base_uri)
                            -- use luv to check if baseDir is a directory
                            local stat = vim.uv.fs_stat(base_dir)
                            return stat ~= nil and stat.type == "directory"
                        end
                    end

                    return true
                end, reg.registerOptions.watchers)

                reg.registerOptions.watchers = filewatching and watchers or {}
            end
        end
        return handler(err, res, ctx, config)
    end
end

return M
