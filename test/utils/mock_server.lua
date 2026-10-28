local M = {}

M.notifications = {}
M.requests = {}
M.responses = {}

local default_responses = {
  ["textDocument/diagnostic"] = function()
    return { kind = "full", items = {} }
  end,
  ["workspace/textDocumentContent"] = function()
    return { text = "namespace Generated {}" }
  end,
  ["textDocument/_vs_onAutoInsert"] = function()
    return nil
  end,
}

function M.server()
  local closing = false
  local srv = {}

  function srv.request(method, params, handler)
    if method == "initialize" then
      handler(nil, {
        capabilities = {
          diagnosticProvider = {
            interFileDependencies = true,
            workspaceDiagnostics = false,
          },
          _vs_onAutoInsertProvider = {
            _vs_triggerCharacters = { "'", "/", "\n", '"' },
          },
        },
      })
    elseif method == "shutdown" then
      handler(nil, nil)
    else
      local respond = M.responses[method] or default_responses[method]
      assert(respond, "Unhandled method: " .. method)
      M.requests[method] = M.requests[method] or {}
      table.insert(M.requests[method], params)
      handler(nil, respond(params))
      return true
    end
  end

  function srv.notify(method, params)
    if method == "exit" then
      closing = true
    elseif method == "solution/open" or method == "project/open" then
      table.insert(M.notifications, { method = method, params = params })
    end
  end

  function srv.is_closing()
    return closing
  end

  function srv.terminate()
    closing = true
  end

  return srv
end

function M.reset()
  M.notifications = {}
  M.requests = {}
  M.responses = {}
end

return M
