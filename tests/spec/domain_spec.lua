local api = require("rosetta")
local config = require("rosetta.config")
local registry = require("rosetta.registry")

test("nested configuration errors identify invalid user input", function()
	for _, options in ipairs({
		{ registry = { xx = true } },
		{
			registry = {
				xx = {
					name = "X",
					translation_name = "X",
					aliases = {},
					default = "xx",
					variants = { xx = true },
				},
			},
		},
		{ checker = { settings = { ltex = { enabled = { 42 } } } } },
	}) do
		local result, err = api.configure(options)
		assert(not result and err.code ~= "internal")
	end
end)

test("command completion handles modifiers and cursor position", function()
	local complete = require("rosetta.commands").complete
	for _, line in ipairs({
		"Rosetta start en",
		"silent Rosetta start en",
		":keepalt Rosetta start en",
	}) do
		assert(vim.tbl_contains(complete("en", line, #line), "en-gb"))
	end
	eq({ "start", "stop" }, complete("st", "silent Rosetta st ignored", #"silent Rosetta st"))
end)

test("invalid configuration preserves the committed candidate", function()
	assert(api.configure({ languages = { "fr", "en" } }))
	local before = config.get()
	local result, err = api.configure({ languages = { "en-US", "en-GB" } })
	assert(not result and err.code == "languages")
	assert(config.get() == before)
	assert(api.configure({}))
	eq({ "ca", "de", "en" }, config.get().languages)
end)

test("aliases and retained variants resolve consistently", function()
	local resolver = config.get().resolver
	local slots = registry.resolve_list(resolver, { "cat", "deu", "en-GB" })
	eq(
		{ "ca", "de", "en" },
		vim.tbl_map(function(slot)
			return slot.id
		end, slots)
	)
	local retained = registry.resolve_list(resolver, { "ca", "de", "eng" }, slots)
	eq("en-GB", retained[3].variant)
end)

test("logical text preserves LF segments and rejects malformed scalars", function()
	local text = require("rosetta.text")
	local lines = { "first", "", "last", "" }
	eq(lines, text.decode(text.encode(lines)))
	assert(not text.valid(string.char(0xC0, 0x80)))
	assert(not text.valid(string.char(0xED, 0xA0, 0x80)))
	assert(not text.encode({ "embedded\nNUL" }))
	assert(not text.decode("\r\n"))
end)

test("HTTP framing handles split interim headers and bounds collection", function()
	local transport = require("rosetta.transport")
	local collector = transport.collector({ header_bytes = 128, body_bytes = 5, stderr_bytes = 2 })
	for _, chunk in ipairs({ "HTTP/1.1 100 Continue\r\n\r", "\nHTTP/2 200 OK\r\n\r", "\nhello" }) do
		assert(not collector.stdout(chunk))
	end
	eq(200, collector.status)
	eq("hello", table.concat(collector.chunks))
	eq("body limit", collector.stdout("!"))
	eq("stderr limit", collector.stderr("abc"))
end)
