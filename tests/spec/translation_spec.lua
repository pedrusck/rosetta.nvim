---@diagnostic disable: duplicate-set-field
local helpers = dofile("tests/helpers.lua")

test("pending delivery cancels once and ignores late responses", function()
	local f = helpers.translation()
	f.mode = "i"
	f.run()
	f.requests[3].reply(helpers.response("German"))
	eq("waiting", f.translation.status(f.registrations[2]).outcome)
	eq({ "Original target" }, vim.api.nvim_buf_get_lines(f.registrations[2].buf, 0, -1, false))
	f.translation.cancel()
	f.requests[4].reply(helpers.response("Late French"))
	f.mode = "n"
	f.translation.deliver()
	drain()
	eq(1, #f.completed)
	eq({ de = "cancelled", fr = "cancelled" }, f.completed[1].outcomes)
end)

test("preflight failure preserves current work and successful supersession cancels it", function()
	local f = helpers.translation()
	f.run()
	f.config.provider.profiles.first.context = 1
	-- Activated profiles are captured; explicitly reactivate to test snapshot semantics.
	local original_capture = f.provider.capture
	f.provider.capture = function()
		local execution = original_capture()
		execution.prepare = function()
			require("rosetta.util").fail("budgets", "fixture rejection")
		end
		return execution
	end
	local ok, err = pcall(f.run)
	assert(not ok and err.code == "budgets")
	assert(not f.requests[3].cancelled)
	eq(4, #f.requests)
	f.provider.capture = original_capture
	f.run()
	assert(f.requests[3].cancelled and f.requests[4].cancelled)
	f.requests[3].reply(helpers.response("obsolete"))
	f.requests[5].reply(helpers.response("German"))
	f.requests[6].reply(helpers.response("French"))
	drain()
	eq(2, #f.completed)
	eq({ de = "succeeded", fr = "succeeded" }, f.completed[2].outcomes)
end)

test("captured translations survive model selection and replace manual target edits", function()
	local f = helpers.translation()
	f.run()
	local _, select = f.provider.model_choices()
	select("second")
	vim.api.nvim_buf_set_lines(f.registrations[2].buf, 0, -1, false, { "manual edit after dispatch" })
	f.requests[3].reply(helpers.response("German"))
	f.requests[4].reply(helpers.response("French"))
	drain()
	eq({ "German" }, vim.api.nvim_buf_get_lines(f.registrations[2].buf, 0, -1, false))
	eq({ de = "succeeded", fr = "succeeded" }, f.completed[1].outcomes)
end)

test("locale invalidation cancels a target while siblings continue", function()
	local f = helpers.translation()
	f.run()
	f.translation.invalidate(f.registrations[2])
	f.session.locale_changed(f.registrations[2])
	f.translation.changed(f.registrations[2], false)
	f.requests[3].reply(helpers.response("obsolete"))
	f.requests[4].reply(helpers.response("French"))
	drain()
	eq({ de = "cancelled", fr = "succeeded" }, f.completed[1].outcomes)
	eq("variant_changed", f.translation.status(f.registrations[2]).pending)
end)

test("delivery revalidates modifiability and provider generation", function()
	local f = helpers.translation()
	f.mode = "i"
	f.run()
	f.requests[3].reply(helpers.response("German"))
	f.requests[4].reply(helpers.response("French"))
	vim.bo[f.registrations[2].buf].modifiable = false
	f.mode = "n"
	f.translation.deliver()
	drain()
	eq({ de = "failed", fr = "succeeded" }, f.completed[1].outcomes)
	vim.bo[f.registrations[2].buf].modifiable = true
	f.mode = "i"
	f.run()
	f.requests[5].reply(helpers.response("new German"))
	f.requests[6].reply(helpers.response("new French"))
	f.provider.stop()
	f.mode = "n"
	f.translation.deliver()
	drain()
	eq({ de = "cancelled", fr = "cancelled" }, f.completed[2].outcomes)
end)
