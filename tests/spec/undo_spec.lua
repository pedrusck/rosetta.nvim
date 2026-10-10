test("delivery isolates undo from typing and identical output creates no entry", function()
	-- Separate RPC requests let the child return to its input loop between user
	-- edits and response delivery. A single Lua script would join their undo blocks.
	local channel = vim.fn.jobstart(
		{ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" },
		{ rpc = true }
	)
	local function lua(code)
		return vim.rpcrequest(channel, "nvim_exec_lua", code, {})
	end
	local ok, err = xpcall(function()
		lua("vim.opt.runtimepath:prepend(" .. string.format("%q", vim.fn.getcwd()) .. ")")
		lua([[helpers = dofile('tests/helpers.lua'); fixture = helpers.translation(); fixture.run();
      target = fixture.registrations[2].buf; vim.api.nvim_set_current_buf(target)]])
		local function input(keys, expected)
			vim.rpcrequest(channel, "nvim_input", keys)
			assert(
				vim.wait(2000, function()
					return vim.deep_equal(expected, lua("return vim.api.nvim_buf_get_lines(target, 0, -1, false)"))
						and lua("return vim.api.nvim_get_mode().mode") == "n"
				end),
				"editor input did not produce expected text"
			)
		end
		input("ccmanual edit\027", { "manual edit" })
		lua([[fixture.requests[3].reply(helpers.response('Translated\nsecond line'));
      fixture.requests[4].reply(helpers.response('French'))]])
		input("u", { "manual edit" })
		input("\018", { "Translated", "second line" })
		input("GA typed afterwards\027", { "Translated", "second line typed afterwards" })
		input("u", { "Translated", "second line" })
		local sequence = lua("return vim.fn.undotree().seq_cur")
		lua([[vim.api.nvim_set_current_buf(fixture.registrations[1].buf); fixture.run();
      fixture.requests[5].reply(helpers.response('Translated\nsecond line'));
      fixture.requests[6].reply(helpers.response('French')); vim.api.nvim_set_current_buf(target)]])
		eq(sequence, lua("return vim.fn.undotree().seq_cur"))
	end, debug.traceback)
	vim.fn.jobstop(channel)
	assert(ok, err)
end)
