---@diagnostic disable: duplicate-set-field
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.undofile = false
vim.notify = function() end

local failures = 0
_G.test = function(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. "\n" .. err)
	end
end
_G.eq = function(expected, actual)
	assert(vim.deep_equal(expected, actual), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
_G.drain = function()
	local done = false
	vim.schedule(function()
		done = true
	end)
	assert(
		vim.wait(1000, function()
			return done
		end),
		"scheduled callback did not run"
	)
end

local ok, err = xpcall(function()
	dofile(arg[1])
end, debug.traceback)
if not ok then
	print(err)
	failures = failures + 1
end
vim.cmd(failures > 0 and "cquit 1" or "qall!")
