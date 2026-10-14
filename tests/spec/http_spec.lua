test("curl adapter sends a bounded authenticated request and removes its body file", function()
	local uv = vim.uv
	local server = assert(uv.new_tcp())
	assert(server:bind("127.0.0.1", 0))
	local address = assert(server:getsockname())
	local clients, received = {}, ""
	---@type {status: integer?, body: string, error: string?}?
	local result
	assert(server:listen(8, function(err)
		assert(not err)
		local client = assert(uv.new_tcp())
		clients[#clients + 1] = client
		assert(server:accept(client))
		local replied = false
		client:read_start(function(read_error, chunk)
			assert(not read_error)
			if not chunk then
				return
			end
			received = received .. chunk
			local boundary = received:find("\r\n\r\n", 1, true)
			local length = tonumber(received:lower():match("content%-length: (%d+)"))
			if not replied and boundary and length and #received - boundary - 3 >= length then
				replied = true
				local body = '{"fixture":true}'
				client:write(
					"HTTP/1.1 200 OK\r\nContent-Length: " .. #body .. "\r\nConnection: close\r\n\r\n" .. body,
					function()
						client:read_stop()
						client:close()
					end
				)
			end
		end)
	end))
	local files = require("rosetta.files")
	local ok, problem = xpcall(function()
		assert(require("rosetta").configure({ http = { timeout_ms = 2000 } }))
		local context = {
			config = { base_url = "http://127.0.0.1:" .. address.port, allow_http = true },
			key = "fixture-key",
			credential_env = "ROSETTA_FIXTURE_KEY",
		}
		require("rosetta.transport").http(
			context,
			"POST",
			"/chat/completions",
			{ messages = { "fixture document" } },
			function(response)
				result = response
			end
		)
		local root = files.directory()
		assert(
			vim.wait(5000, function()
				return result ~= nil
			end),
			"local curl request timed out"
		)
		assert(result)
		assert(not result.error, result.error)
		eq(200, result.status)
		eq('{"fixture":true}', result.body)
		assert(received:find("POST /chat/completions", 1, true))
		assert(received:find("Authorization: Bearer fixture-key", 1, true))
		assert(received:find("fixture document", 1, true))
		eq({}, vim.fn.glob(root .. "/*.request.json", false, true))
	end, debug.traceback)
	for _, client in ipairs(clients) do
		if not client:is_closing() then
			client:close()
		end
	end
	server:close()
	require("rosetta.process").shutdown()
	files.cleanup(nil, true)
	assert(ok, problem)
end)
