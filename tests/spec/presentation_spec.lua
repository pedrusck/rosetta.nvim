test("refresh recovers from exceptions, coalesces work and preserves user overrides", function()
	local win = vim.api.nvim_get_current_win()
	local reg = {}
	local calls, fail, live = 0, true, true
	local original = vim.wo[win].winbar
	local presentation = require("rosetta.presentation").new({
		is_alive = function()
			return true
		end,
		registration = function(w)
			return w == win and live and reg or nil
		end,
		native_available = function()
			return false
		end,
		model = function()
			calls = calls + 1
			if fail then
				fail = false
				error("injected rendering failure")
			end
			return { name = "English 100%", checking = "Spell", translation = "Ready" }
		end,
	})
	presentation.refresh()
	presentation.refresh()
	eq(2, calls)
	eq("English 100%% | Spell | Ready", vim.wo[win].winbar)
	for _ = 1, 10 do
		presentation.request_refresh()
	end
	drain()
	eq(3, calls)
	vim.wo[win].winbar = "user choice"
	presentation.refresh()
	eq("user choice", vim.wo[win].winbar)
	live = false
	presentation.refresh()
	eq("user choice", vim.wo[win].winbar)
	vim.wo[win].winbar = original
end)

test("view status precedence uses semantic pending reasons", function()
	local view = require("rosetta.view")
	local translation = { outcome = "failed", pending = "language_changed" }
	eq("Stopped", view.translation("stopped", { ready = true }, translation))
	eq("Preparing", view.translation("active", { ready = false, label = "Preparing" }, translation))
	eq("Request error", view.translation("active", { ready = true }, translation))
	translation.outcome = "succeeded"
	eq("Language changed", view.translation("active", { ready = true }, translation))
end)

test("layout planner protects auxiliary leaves and retains row orientation on growth", function()
	local plan = require("rosetta.layout_plan")
	local managed = { "row", { { "leaf", 1 }, { "leaf", 2 } } }
	local tree = { "col", { managed, { "leaf", 3 } } }
	eq(managed, plan.subtree(tree, { [1] = true, [2] = true }))
	assert(not plan.subtree(tree, { [1] = true, [3] = true }))
	eq("rows", plan.orientation("columns", false, false, 30, 45))
	eq("rows", plan.orientation("rows", false, true, 100, 45))
	eq("columns", plan.orientation("rows", true, true, 100, 45))
end)
