local Layout = {}
local plan = require("rosetta.layout_plan")

function Layout.new(deps)
	local M = {}
	local dimensions, pending
	local state = { slots = {} }

	local function synchronize()
		local windows = {}
		for _, pane in ipairs(state.slots) do
			if pane.registration then
				windows[pane.registration] = pane.win
			end
		end
		state.slots = {}
		for _, slot in ipairs(deps.slots()) do
			if deps.is_live(slot.registration) then
				state.slots[#state.slots + 1] = { registration = slot.registration, win = windows[slot.registration] }
			end
		end
	end

	function M.tab()
		return state.tab
	end

	local function managed(state)
		local result = {}
		for _, slot in ipairs(state.slots) do
			if
				slot.win
				and vim.api.nvim_win_is_valid(slot.win)
				and vim.api.nvim_win_get_tabpage(slot.win) == state.tab
				and slot.registration
				and vim.api.nvim_win_get_buf(slot.win) == slot.registration.buf
			then
				result[#result + 1] = slot.win
			else
				slot.win = nil
			end
		end
		return result
	end

	local function usable(win)
		local info = vim.fn.getwininfo(win)[1]
		return info and info.width - info.textoff or 0
	end

	local function arrange(state, retry_columns, restore)
		local owned = managed(state)
		local config = deps.config().layout
		if #owned == 0 then
			if not restore then
				return true
			end
			-- Existing auxiliary-only tabs are protected; add a managed split there.
			local anchor = vim.api.nvim_tabpage_get_win(state.tab)
			local first = state.slots[1]
			vim.api.nvim_win_call(anchor, function()
				vim.cmd("belowright sbuffer " .. first.registration.buf)
				anchor = vim.api.nvim_get_current_win()
			end)
			vim.api.nvim_win_set_buf(anchor, first.registration.buf)
			first.win = anchor
			owned = { anchor }
		end
		local set = {}
		for _, win in ipairs(owned) do
			set[win] = true
		end
		local tree = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(state.tab))
		local subtree = plan.subtree(tree, set)
		if not subtree then
			require("rosetta.util").notify(
				"Protected windows prevent reflow; move/close auxiliary windows, then run :Rosetta layout"
			)
			return false
		end
		local slots = {}
		for _, slot in ipairs(state.slots) do
			if restore or slot.win then
				slots[#slots + 1] = slot
			end
		end
		local mincol = math.huge
		local left, right = math.huge, 0
		local gutter = 0
		for _, win in ipairs(owned) do
			local info = vim.fn.getwininfo(win)[1]
			mincol = math.min(mincol, usable(win))
			left, right = math.min(left, info.wincol), math.max(right, info.wincol + info.width)
			gutter = math.max(gutter, info.textoff)
		end
		local columns_fit = math.floor((right - left - (#slots - 1)) / #slots) - gutter >= config.min_columns
		local orientation = plan.orientation(state.orientation, retry_columns, columns_fit, mincol, config.min_columns)
		local ordered = true
		local displayed = plan.leaves(subtree)
		for i, slot in ipairs(slots) do
			if displayed[i] ~= slot.win then
				ordered = false
			end
		end
		if #owned == #slots and state.orientation == orientation and not retry_columns and ordered then
			return true
		end
		for _, slot in ipairs(slots) do
			local bh = vim.bo[slot.registration.buf].bufhidden
			if bh == "unload" or bh == "delete" or bh == "wipe" then
				require("rosetta.util").notify(
					"Reflow would retire a buffer with bufhidden=" .. bh .. "; adjust it before :Rosetta layout"
				)
				return false
			end
		end
		local anchor = owned[1]
		for i = #owned, 2, -1 do
			vim.api.nvim_win_close(owned[i], true)
		end
		for _, slot in ipairs(slots) do
			slot.win = nil
		end
		vim.api.nvim_win_set_buf(anchor, slots[1].registration.buf)
		slots[1].win = anchor
		local windows = { anchor }
		for i = 2, #slots do
			local created
			vim.api.nvim_win_call(windows[#windows], function()
				vim.cmd(orientation == "columns" and "belowright vsplit" or "belowright split")
				created = vim.api.nvim_get_current_win()
				vim.api.nvim_win_set_buf(created, slots[i].registration.buf)
			end)
			slots[i].win, windows[#windows + 1] = created, created
		end
		state.orientation = orientation
		-- Equalize only managed siblings; never use whole-tab wincmd = or edge moves.
		local extent = 0
		for _, win in ipairs(windows) do
			extent = extent
				+ (orientation == "columns" and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win))
		end
		local size = math.max(1, math.floor(extent / #windows))
		for _, win in ipairs(windows) do
			pcall(orientation == "columns" and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height, win, size)
		end
		return true
	end

	function M.restore(retry_columns)
		synchronize()
		if #state.slots == 0 then
			return false
		end
		if not state.tab or not vim.api.nvim_tabpage_is_valid(state.tab) then
			vim.cmd("tab sbuffer " .. state.slots[1].registration.buf)
			state.tab = vim.api.nvim_get_current_tabpage()
			local first = state.slots[1]
			vim.api.nvim_win_set_buf(0, first.registration.buf)
			first.win = vim.api.nvim_get_current_win()
		else
			vim.api.nvim_set_current_tabpage(state.tab)
		end
		dimensions = { vim.o.columns, vim.o.lines }
		return arrange(state, retry_columns, true)
	end

	function M.resize()
		local next_dimensions = { vim.o.columns, vim.o.lines }
		if vim.deep_equal(dimensions, next_dimensions) then
			return
		end
		dimensions = next_dimensions
		if pending then
			return
		end
		pending = true
		vim.schedule(function()
			pending = false
			if
				not deps.is_alive()
				or not state.tab
				or not vim.api.nvim_tabpage_is_valid(state.tab)
				or state.orientation ~= "columns"
			then
				return
			end
			synchronize()
			local ok = pcall(arrange, state, false, false)
			if not ok then
				require("rosetta.util").notify("Partial resize; use :Rosetta layout for explicit restoration")
			end
			deps.on_changed()
		end)
	end

	return M
end

return Layout
