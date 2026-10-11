local Presentation = {}

function Presentation.new(deps)
	local M = {}
	local overrides, refreshing, pending = {}, false, false

	local function restore(win, record)
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		for key, entry in pairs(record.options) do
			if vim.wo[win][key] == entry.last then
				vim.wo[win][key] = entry.before
			end
		end
	end

	local function set(win, record, name, value)
		local entry = record.options[name]
		if not entry then
			entry = { before = vim.wo[win][name], last = vim.wo[win][name] }
			record.options[name] = entry
		end
		if vim.wo[win][name] ~= entry.last then
			return
		end -- a later user override wins
		if entry.last ~= value then
			vim.wo[win][name] = value
			entry.last = value
		end
	end

	local function render()
		for win, record in pairs(overrides) do
			if not vim.api.nvim_win_is_valid(win) or deps.registration(win) ~= record.reg then
				restore(win, record)
				overrides[win] = nil
			end
		end
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local reg = deps.registration(win)
			if reg then
				local record = overrides[win] or { reg = reg, options = {} }
				overrides[win] = record
				-- Set spell before building the label so it reflects effective options.
				set(win, record, "spell", deps.native_available(reg))
				set(win, record, "winbar", require("rosetta.view").winbar(deps.model(reg, win)))
			end
		end
	end

	function M.refresh()
		if refreshing or not deps.is_alive() then
			return
		end
		refreshing = true
		local ok = pcall(render)
		refreshing = false -- recover even if a buffer/window disappeared during rendering
		if not ok then
			require("rosetta.util").notify("Presentation refresh failed; the next update will retry")
		end
	end

	function M.request_refresh()
		if pending or not deps.is_alive() then
			return
		end
		pending = true
		vim.schedule(function()
			pending = false
			M.refresh()
		end)
	end

	return M
end

return Presentation
