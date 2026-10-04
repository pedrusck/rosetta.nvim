local u = require("rosetta.util")
local M = {}

-- curl --include emits textual response headers even for HTTP/2. CONNECT headers
-- are suppressed. After the final header, every byte belongs to the body.
function M.collector(limits)
	local out = { status = nil, chunks = {}, bytes = 0, header_bytes = 0, stderr_bytes = 0 }
	local header, body = "", false
	function out.stdout(chunk)
		if not body then
			header = header .. chunk
			while true do
				local boundary = header:find("\r\n\r\n", 1, true)
				if not boundary then
					if out.header_bytes + #header > limits.header_bytes then
						return "header limit"
					end
					return
				end
				local block = header:sub(1, boundary + 3)
				out.header_bytes = out.header_bytes + #block
				if out.header_bytes > limits.header_bytes then
					return "header limit"
				end
				local status = tonumber(block:match("^HTTP/[%d.]+ (%d%d%d)[ \r]"))
				if not status then
					return "invalid HTTP framing"
				end
				header = header:sub(boundary + 4)
				if status >= 200 then
					out.status, body, chunk = status, true, header
					header = ""
					break
				end
			end
		end
		out.bytes = out.bytes + #chunk
		if out.bytes > limits.body_bytes then
			return "body limit"
		end
		out.chunks[#out.chunks + 1] = chunk
	end
	function out.stderr(chunk)
		out.stderr_bytes = out.stderr_bytes + #chunk
		if out.stderr_bytes > limits.stderr_bytes then
			return "stderr limit"
		end
		-- Never retain/report raw curl output (it can contain hostile endpoint data).
	end
	return out
end

function M.http(context, method, route, request, callback)
	local config = require("rosetta.config").get()
	local limits = vim.deepcopy(config.http)
	local collector = M.collector(limits)
	local files = require("rosetta.files")
	local path
	if request then
		local ok, body = pcall(vim.json.encode, request)
		if not ok then
			vim.schedule(function()
				callback({ error = "JSON encoding failed" })
			end)
			return { cancel = function() end }
		end
		local err
		path, err = u.try(files.request, body)
		if not path then
			vim.schedule(function()
				callback({ error = err and err.message or "Could not create request file" })
			end)
			return { cancel = function() end }
		end
	end
	local argv = {
		limits.executable,
		"--disable",
		"--globoff",
		"--silent",
		"--show-error",
		"--include",
		"--suppress-connect-headers",
		"--no-location",
		"--retry",
		"0",
		"--proto",
		context.config.allow_http and "=http,https" or "=https",
		"--max-time",
		tostring(limits.timeout_ms / 1000),
		"--request",
		method,
		"--header",
		"@-",
	}
	if path then
		vim.list_extend(argv, { "--header", "Content-Type: application/json", "--data-binary", "@" .. path })
	end
	vim.list_extend(argv, { "--url", context.config.base_url .. route })
	local env = vim.fn.environ()
	env[context.credential_env or "ROSETTA_API_KEY"] = nil
	env.SSLKEYLOGFILE, env.CURL_SSL_BACKEND = nil, nil
	return require("rosetta.process").run(argv, {
		stdin = "Authorization: Bearer " .. context.key .. "\n",
		env = env,
		timeout_ms = limits.timeout_ms,
		stdout = collector.stdout,
		stderr = collector.stderr,
	}, function(err, result)
		if path and not files.remove(path) then
			u.notify("Could not remove an owned request file; exit cleanup will retry")
		end
		local status = collector.status
		callback({
			status = status,
			body = table.concat(collector.chunks),
			error = err
				or (result.code ~= 0 and "HTTP process failed")
				or (not status and "Missing HTTP status")
				or nil,
		})
		collector.chunks = {}
	end)
end

return M
