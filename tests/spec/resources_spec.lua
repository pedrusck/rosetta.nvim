test("cleanup deletes owned paths and leaves unknown files intact", function()
	local files = require("rosetta.files")
	local dir = files.directory()
	local unknown = dir .. "/user-export.txt"
	vim.fn.writefile({ "keep" }, unknown)
	local owned = files.request("fixture body")
	assert(vim.uv.fs_stat(owned))
	assert(files.cleanup(nil, true))
	assert(not vim.uv.fs_stat(owned))
	assert(vim.uv.fs_stat(unknown))
	assert(vim.uv.fs_unlink(unknown))
	files.prune()
	assert(not vim.uv.fs_stat(dir))
end)

test("process timeout and output bounds complete once", function()
	local process = require("rosetta.process")
	local results = {}
	process.run({ "sh", "-c", "printf excessive" }, {
		timeout_ms = 1000,
		stdout = function(chunk)
			if #chunk > 2 then
				return "output limit"
			end
		end,
		stderr = function() end,
	}, function(err)
		results[#results + 1] = err
	end)
	assert(vim.wait(3000, function()
		return #results == 1
	end))
	eq("output limit", results[1])
	local handle = process.run({ "sh", "-c", "sleep 10" }, {
		timeout_ms = 25,
		stdout = function() end,
		stderr = function() end,
	}, function(err)
		results[#results + 1] = err
	end)
	assert(vim.wait(3000, function()
		return #results == 2
	end))
	eq("timeout", results[2])
	handle.cancel()
	drain()
	eq(2, #results)
end)

test("credential command failure has no environment fallback", function()
	local credentials = require("rosetta.credentials")
	vim.env.ROSETTA_TEST_KEY = "environment-key"
	local completed, key, err
	credentials.read({
		command = { "sh", "-c", "exit 1" },
		env = "ROSETTA_TEST_KEY",
		timeout_ms = 1000,
		max_bytes = 128,
	}, function(value, problem)
		key, err, completed = value, problem, true
	end)
	assert(vim.wait(3000, function()
		return completed
	end))
	assert(not key and err)
	eq("key", credentials.parse("key\r\n"))
	assert(not credentials.parse("key\n\n"))
	vim.env.ROSETTA_TEST_KEY = nil
end)
