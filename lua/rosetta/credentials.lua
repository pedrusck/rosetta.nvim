local M = {}

function M.parse(value)
	if type(value) ~= "string" then
		return nil
	end
	value = value:gsub("\r?\n$", "", 1)
	if value == "" or value:find("[%z\1-\32\127]") then
		return nil
	end
	return value
end

-- A cancelled environment read is suppressed. Process reads finish through the
-- process supervisor; the provider's context token rejects cancelled results.
function M.read(config, callback)
	if not config.command then
		local key = M.parse(vim.env[config.env])
		local cancelled = false
		vim.schedule(function()
			if not cancelled then
				callback(key, key and nil or "Missing or invalid environment credential")
			end
			key = nil
		end)
		return {
			cancel = function()
				cancelled = true
				key = nil
			end,
		}
	end
	local chunks, size, errors = {}, 0, 0
	return require("rosetta.process").run(config.command, {
		timeout_ms = config.timeout_ms,
		stdout = function(chunk)
			size = size + #chunk
			if size > config.max_bytes then
				return "credential output limit"
			end
			chunks[#chunks + 1] = chunk
		end,
		stderr = function(chunk)
			errors = errors + #chunk
			if errors > config.max_bytes then
				return "credential error-output limit"
			end
		end,
	}, function(err, result)
		local key = not err and result.code == 0 and M.parse(table.concat(chunks)) or nil
		chunks = {}
		callback(key, key and nil or ("Credential command failed (" .. (err or "exit/framing") .. ")"))
	end)
end

return M
