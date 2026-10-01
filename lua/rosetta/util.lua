local M = {}

function M.fail(code, message)
	error({ code = code, message = message }, 0)
end

function M.check(condition, code, message)
	if not condition then
		M.fail(code, message)
	end
end

function M.try(fn, ...)
	return M.try_at("operation", fn, ...)
end

function M.try_at(operation, fn, ...)
	local ok, value = pcall(fn, ...)
	if ok then
		return value
	end
	if type(value) == "table" and value.code and value.message then
		return nil, value
	end
	return nil,
		{
			code = "internal",
			message = "Rosetta " .. operation .. " failed; no configuration or process output was logged",
		}
end

function M.notify(message, level)
	vim.schedule(function()
		vim.notify("Rosetta: " .. message, level or vim.log.levels.WARN)
	end)
end

function M.positive(value)
	return type(value) == "number" and value > 0 and value < math.huge and value == value
end

function M.integer(value)
	return M.positive(value) and value == math.floor(value)
end

function M.keys(value, allowed, path)
	M.check(type(value) == "table", "config", path .. " must be a table")
	for key in pairs(value) do
		M.check(allowed[key], "config", "Unknown option in " .. path)
	end
end

function M.string(value)
	return type(value) == "string" and value ~= "" and not value:find("[%z\1-\31\127]")
end

function M.list(value)
	return type(value) == "table" and vim.islist(value)
end

function M.callback(callback, result)
	if callback then
		vim.schedule(function()
			local ok = pcall(callback, result)
			if not ok then
				M.notify("An operation callback failed")
			end
		end)
	end
end

function M.options(opts)
	opts = opts or {}
	M.keys(opts, { on_complete = true }, "operation options")
	M.check(
		opts.on_complete == nil or type(opts.on_complete) == "function",
		"arguments",
		"on_complete must be a function"
	)
	return opts
end

return M
