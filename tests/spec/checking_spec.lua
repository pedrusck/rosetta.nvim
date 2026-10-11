---@diagnostic disable: duplicate-set-field
local config = require("rosetta.config").candidate({
	checker = {
		enabled = true,
		cmd = { "sh" },
		locales = { ["en-US"] = true },
	},
})
local session = require("rosetta.session").new()
local slot = require("rosetta.registry").resolve(config.resolver, "en")
local buf = vim.api.nvim_create_buf(true, false)
local reg = session.create(buf, slot)
slot.registration = reg
session.commit({ slot })
local clients, startup, next_id = {}, {}, 0
vim.lsp.start = function(options)
	next_id = next_id + 1
	local client = { id = next_id, settings = options.settings, initialized = true, name = options.name }
	function client:stop()
		self.stopped = true
	end
	function client:is_stopped()
		return self.stopped or false
	end
	function client:request(_, _, callback)
		if callback then
			callback(nil, {})
		end
		return true, 1
	end
	function client:notify()
		return true
	end
	clients[next_id], startup[next_id] = client, options
	options.on_init(client)
	options.on_attach(client)
	return next_id
end
vim.lsp.get_client_by_id = function(id)
	return clients[id]
end
vim.lsp.get_clients = function()
	return {}
end
vim.lsp.buf_detach_client = function() end
vim.lsp.handlers["textDocument/publishDiagnostics"] = function() end
local checker = require("rosetta.checking").new({
	config = function()
		return config
	end,
	is_live = session.is_live,
	on_changed = function() end,
})

test("checker captures profile and correlates diagnostics with outbound versions", function()
	checker.attach(reg)
	local record = checker.record(reg)
	local client = clients[record.client]
	local uri = vim.uri_from_bufnr(buf)
	client:notify("textDocument/didOpen", { textDocument = { uri = uri, version = 7 } })
	startup[record.client].handlers["textDocument/publishDiagnostics"](
		nil,
		{ uri = uri, version = 7, diagnostics = {} },
		{}
	)
	assert(record.diagnostics)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "changed" })
	startup[record.client].handlers["textDocument/publishDiagnostics"](
		nil,
		{ uri = uri, version = 7, diagnostics = {} },
		{}
	)
	assert(not record.diagnostics)
	local profile = record.checker_profile
	config.checker.debounce_ms = 987
	checker.attach(reg, true)
	assert(checker.record(reg).checker_profile == profile)
	eq(300, profile.debounce_ms)
	assert(client.stopped)
end)

test("checker label reads cached directive inspection and stale clients cannot update it", function()
	local record = checker.record(reg)
	local old_options = startup[record.client]
	checker.attach(reg)
	local epoch = record.checker_epoch
	old_options.on_exit()
	drain()
	assert(record.ltex_active)
	eq(epoch, record.checker_epoch)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<!-- ltex: language=de-DE -->" })
	checker.inspect(reg)
	eq("LTeX+ document locale unverified", checker.label(reg, vim.api.nvim_get_current_win()))
end)

test("management actions are excluded while ordinary edits remain", function()
	local safe = require("rosetta.checking").safe_actions({
		{ command = "_ltex.addToDictionary" },
		{ command = { command = "_ltex.disableRules" } },
		{ title = "fix", edit = {} },
	})
	eq({ { title = "fix", edit = {} } }, safe)
end)

test("correction snapshots reject changed text, checker epochs and URI changes", function()
	local corrections = require("rosetta.corrections").new({
		is_live = session.is_live,
		checker_record = checker.record,
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "héllo" })
	local snapshot = corrections.snapshot(reg, { line = 0, character = 2 }, "utf-16")
	assert(snapshot)
	eq(3, snapshot.byte)
	assert(corrections.current(snapshot))
	checker.detach(reg)
	assert(not corrections.current(snapshot))
	snapshot = corrections.snapshot(reg, { line = 0, character = 2 }, "utf-16")
	session.renamed(reg)
	assert(not corrections.current(snapshot))
	snapshot = corrections.snapshot(reg, { line = 0, character = 2 }, "utf-16")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited" })
	assert(not corrections.current(snapshot))
end)

require("rosetta.files").cleanup(nil, true)
