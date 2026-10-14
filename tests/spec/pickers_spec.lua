---@diagnostic disable: duplicate-set-field
test("variant picker captures a handle and rejects stale selection", function()
	local api = require("rosetta")
	local picker = require("rosetta.pickers")
	local selection
	picker.open = function(_, _, _, select)
		selection = select
		return { accepted = true }
	end
	assert(api.configure({ languages = { "en", "de" } }))
	assert(api.start())
	local ref = api.registration(api.status().languages[1].buffer)
	local completed = {}
	assert(api.variant(ref, {
		on_complete = function(value)
			completed[#completed + 1] = value
		end,
	}))
	assert(api.reassign(ref, "en-GB"))
	local ok, err = pcall(selection, "en-US")
	assert(not ok and err.code == "stale_picker")
	drain()
	eq(0, #completed)
	assert(api.stop())
	assert(api.variant(ref, {
		on_complete = function(value)
			completed[#completed + 1] = value
		end,
	}))
	assert(selection("en-US"))
	drain()
	eq({ { variant = "en-US" } }, completed)
end)
