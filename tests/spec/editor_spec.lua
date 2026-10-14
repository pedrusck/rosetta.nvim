---@diagnostic disable: duplicate-set-field
local api = require("rosetta")
assert(api.configure({ languages = { "en", "de" } }))

test("rename retains handles, captured checker profile and markdown ownership", function()
	assert(api.start())
	drain()
	local buf = api.status().languages[1].buffer
	local ref = assert(api.registration(buf))
	vim.api.nvim_set_current_buf(buf)
	local renamed = vim.api.nvim_buf_get_name(buf) .. ".renamed"
	vim.cmd("file " .. vim.fn.fnameescape(renamed))
	drain()
	eq(ref, api.registration(buf))
	eq("markdown", vim.bo[buf].filetype)
	assert(vim.b[buf].rosetta_owned)
end)

test("allocation failure preserves previous registrations and language list", function()
	local before = api.status()
	local original = vim.api.nvim_create_buf
	vim.api.nvim_create_buf = function()
		error("injected allocation failure")
	end
	local result, err = api.start({ "en", "de", "fr" })
	vim.api.nvim_create_buf = original
	assert(not result and err.code == "allocation")
	eq(before, api.status())
end)

test("layout preserves auxiliary replacement windows", function()
	local unrelated = vim.api.nvim_create_buf(true, false)
	vim.cmd("belowright split")
	local auxiliary = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(auxiliary, unrelated)
	assert(api.layout())
	assert(vim.api.nvim_win_is_valid(auxiliary))
	eq(unrelated, vim.api.nvim_win_get_buf(auxiliary))
end)

test("unload retires immediately and layout restores empty registration", function()
	local buf = api.status().languages[2].buffer
	local ref = assert(api.registration(buf))
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "not recovered" })
	vim.api.nvim_buf_delete(buf, { force = true, unload = true })
	drain()
	assert(not api.reassign(ref, "de-AT"))
	assert(api.layout())
	local replacement = api.status().languages[2].buffer
	assert(replacement ~= buf)
	eq({ "" }, vim.api.nvim_buf_get_lines(replacement, 0, -1, false))
end)

test("retiring membership restores managed window options", function()
	local buf = api.status().languages[1].buffer
	local win = vim.fn.win_findbuf(buf)[1]
	vim.wo[win].winbar = "user override"
	assert(api.start({ "fr", "de" }))
	drain()
	assert(not vim.b[buf].rosetta_owned)
	assert(vim.api.nvim_win_is_valid(win))
	eq("user override", vim.wo[win].winbar)
end)
