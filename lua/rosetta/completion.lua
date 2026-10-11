local M = {}

function M.supported()
	return false,
		"Correction completion is gated: no consumer has passed all range and stale-acceptance tests yet (G-02)"
end

-- This protocol backend is intentionally not attached by the workbench. Keep
-- the ordinary LSP interface testable while consumer acceptance remains gated.
function M.server(dispatchers, deps)
	local sequence, closing, shutting_down, encoding = 0, false, false, "utf-16"
	local pending, documents = {}, {}
	local function reply(id, err, result)
		local entry = pending[id]
		if not entry then
			return
		end
		pending[id] = nil
		vim.schedule(function()
			entry.callback(err, result)
		end)
	end
	local function cancel(id)
		local entry = pending[id]
		if entry and entry.handle then
			entry.handle.cancel()
		end
		reply(id, { code = -32800, message = "Request cancelled" }, nil)
	end
	local function exit()
		if closing then
			return
		end
		closing = true
		for id in pairs(pending) do
			cancel(id)
		end
		vim.schedule(function()
			dispatchers.on_exit(0, 0)
		end)
	end
	return {
		request = function(method, params, callback)
			sequence = sequence + 1
			local id = sequence
			pending[id] = { callback = callback }
			vim.schedule(function()
				if not pending[id] then
					return
				end
				if closing or (shutting_down and method ~= "shutdown") then
					cancel(id)
					return
				end
				if method == "initialize" then
					local encodings = vim.tbl_get(params, "capabilities", "general", "positionEncodings")
						or { "utf-16" }
					for _, value in ipairs(encodings) do
						if value == "utf-8" or value == "utf-16" or value == "utf-32" then
							encoding = value
							break
						end
					end
					reply(id, nil, {
						capabilities = {
							textDocumentSync = 1,
							positionEncoding = encoding,
							completionProvider = { resolveProvider = false },
						},
					})
				elseif method == "shutdown" then
					shutting_down = true
					for other in pairs(pending) do
						if other ~= id then
							cancel(other)
						end
					end
					reply(id, nil, vim.NIL)
				elseif method == "textDocument/completion" then
					local uri = vim.tbl_get(params, "textDocument", "uri")
					local document = uri and documents[uri]
					if not document then
						reply(id, nil, { isIncomplete = true, items = {} })
						return
					end
					pending[id].uri = uri
					local version = document.version
					local reg = deps.find_uri(uri)
					local snapshot = reg and deps.corrections.snapshot(reg, params.position, encoding)
					if not snapshot then
						reply(id, nil, { isIncomplete = true, items = {} })
						return
					end
					pending[id].handle = deps.corrections.collect(snapshot, function(items)
						local same = documents[uri] == document and document.version == version
						reply(id, nil, { isIncomplete = true, items = same and items or {} })
					end)
				else
					reply(id, { code = -32601, message = "Method not supported" }, nil)
				end
			end)
			return true, id
		end,
		notify = function(method, params)
			if method == "$/cancelRequest" then
				cancel(params.id)
			elseif method == "exit" then
				exit()
			elseif method == "textDocument/didOpen" then
				local doc = params.textDocument
				documents[doc.uri] = { version = doc.version }
			elseif method == "textDocument/didChange" or method == "textDocument/didClose" then
				local doc = params.textDocument
				for id, entry in pairs(pending) do
					if entry.uri == doc.uri then
						cancel(id)
					end
				end
				if method == "textDocument/didClose" then
					documents[doc.uri] = nil
				elseif documents[doc.uri] then
					documents[doc.uri].version = doc.version
				end
			end
			-- Document notifications never create buffers. Actual registration and
			-- changedtick/URI epochs additionally validate the editor document model.
			return not closing
		end,
		is_closing = function()
			return closing
		end,
		terminate = exit,
	}
end

return M
