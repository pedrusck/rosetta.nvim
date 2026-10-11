test("completion backend cancels changed documents once and ignores late collection", function()
	local collections, results = {}, {}
	local reg = {}
	local server = require("rosetta.completion").server({ on_exit = function() end }, {
		find_uri = function()
			return reg
		end,
		corrections = {
			snapshot = function()
				return {}
			end,
			collect = function(_, callback)
				local collection = { reply = callback }
				collections[#collections + 1] = collection
				return {
					cancel = function()
						collection.cancelled = true
					end,
				}
			end,
		},
	})
	server.request("initialize", {}, function(err, result)
		assert(not err and result.capabilities.positionEncoding == "utf-16")
	end)
	drain()
	server.notify("textDocument/didOpen", { textDocument = { uri = "file:///fixture", version = 1 } })
	server.request(
		"textDocument/completion",
		{ textDocument = { uri = "file:///fixture" }, position = { line = 0, character = 1 } },
		function(err, result)
			results[#results + 1] = { err = err, result = result }
		end
	)
	drain()
	eq(1, #collections)
	server.notify("textDocument/didChange", { textDocument = { uri = "file:///fixture", version = 2 } })
	collections[1].reply({ { label = "stale" } })
	drain()
	assert(collections[1].cancelled)
	eq(1, #results)
	eq(-32800, results[1].err.code)
	server.terminate()
	assert(server.is_closing())
	eq(false, require("rosetta.completion").supported())
end)
