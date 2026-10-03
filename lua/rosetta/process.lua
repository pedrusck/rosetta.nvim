local M = {}
local active = {}

local function close(timer)
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

-- Stream consumers run in libuv callbacks and must not call editor APIs.
-- Completion is always scheduled, including spawn failure and cancellation.
function M.run(argv, options, callback)
	local process, timer, escalation, ended, failure
	local handle = {}
	local function signal(name)
		if process and not ended then
			pcall(vim.uv.kill, -process.pid, name)
		end
	end
	local function abort(reason)
		if ended or failure then
			return
		end
		failure = reason
		signal("sigterm")
		escalation = vim.uv.new_timer()
		if not escalation then
			signal("sigkill")
			return
		end
		escalation:start(200, 0, function()
			signal("sigkill")
			close(escalation)
		end)
	end
	function handle.cancel()
		abort("cancelled")
	end
	function handle.kill()
		signal("sigkill")
	end
	local function stream(consumer)
		return function(err, data)
			if ended or failure then
				return
			end
			if err then
				abort("stream failure")
				return
			end
			if data then
				local ok, problem = pcall(consumer, data)
				if not ok then
					abort("collection failure")
				elseif problem then
					abort(problem)
				end
			end
		end
	end
	local ok, spawned = pcall(vim.system, argv, {
		detach = true,
		text = false,
		stdin = options.stdin,
		env = options.env,
		clear_env = options.env ~= nil,
		stdout = stream(options.stdout),
		stderr = stream(options.stderr),
	}, function(result)
		-- Kill descendants even when the group leader exits first on TERM.
		if failure then
			signal("sigkill")
		end
		ended = true
		close(timer)
		close(escalation)
		active[handle] = nil
		vim.schedule(function()
			callback(failure, result)
		end)
	end)
	if not ok then
		ended = true
		vim.schedule(function()
			callback("spawn failure", { code = -1 })
		end)
		return handle
	end
	process = spawned
	active[handle] = true
	timer = vim.uv.new_timer()
	if not timer then
		abort("timer allocation failed")
		return handle
	end
	timer:start(options.timeout_ms, 0, function()
		abort("timeout")
	end)
	return handle
end

function M.shutdown()
	for handle in pairs(active) do
		handle.cancel()
		handle.kill()
	end
end

return M
