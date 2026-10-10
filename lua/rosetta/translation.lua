local u = require("rosetta.util")
local Translation = {}

function Translation.new(deps)
	local M = {}
	local session = deps.session
	local operation, serial = nil, 0
	local states = setmetatable({}, { __mode = "k" })

	local function state(reg)
		if not states[reg] then
			states[reg] = {}
		end
		return states[reg]
	end

	function M.status(reg)
		return vim.deepcopy(state(reg))
	end
	function M.changed(reg, identity)
		local current = state(reg)
		if identity or current.pending == "language_changed" then
			current.pending = "language_changed"
		else
			current.pending = "variant_changed"
		end
		current.outcome = nil
	end

	local function finish(op, target, outcome)
		if target.finished then
			return
		end
		target.finished, target.lines, target.request = true, nil, nil
		op.remaining = op.remaining - 1
		op.results[target.language] = outcome
		if session.is_live(target.reg) and target.reg.locale_epoch == target.locale_epoch then
			state(target.reg).outcome = outcome
		end
		if op.remaining == 0 then
			if operation == op then
				operation = nil
			end
			u.callback(op.callback, { id = op.id, outcomes = vim.deepcopy(op.results) })
		end
		deps.on_changed()
	end

	function M.cancel()
		local op = operation
		operation = nil
		if not op then
			return
		end
		for _, target in ipairs(op.targets) do
			if target.handle then
				target.handle.cancel()
			end
			finish(op, target, "cancelled")
		end
	end

	function M.invalidate(reg)
		local op = operation
		if not op then
			return
		end
		if op.source == reg then
			M.cancel()
			return
		end
		for _, target in ipairs(op.targets) do
			if target.reg == reg then
				if target.handle then
					target.handle.cancel()
				end
				finish(op, target, "cancelled")
			end
		end
	end

	function M.eligible(buf)
		-- Zero undolevels uses Vi toggle semantics and does not meet isolated-history
		-- guarantees. A local -123456 means use the global undolevels value.
		local levels = vim.bo[buf].undolevels
		if levels == -123456 then
			levels = vim.go.undolevels
		end
		return vim.bo[buf].modifiable and levels > 0 and not vim.o.cpoptions:find("u", 1, true)
	end

	local function current(op, target)
		return operation == op
			and session.status() == "active"
			and op.execution.is_current()
			and session.is_live(op.source)
			and op.source.locale_epoch == op.source_locale_epoch
			and session.is_live(target.reg)
			and target.reg.locale_epoch == target.locale_epoch
	end

	function M.deliver()
		if deps.mode() ~= "n" then
			return
		end
		local op = operation
		if not op then
			return
		end
		for _, target in ipairs(op.targets) do
			if not target.finished and target.lines then
				if not current(op, target) then
					finish(op, target, "cancelled")
				elseif not M.eligible(target.reg.buf) then
					u.notify(target.language .. ": target is no longer modifiable with supported native undo")
					finish(op, target, "failed")
				else
					local old = vim.api.nvim_buf_get_lines(target.reg.buf, 0, -1, false)
					local ok = true
					if not vim.deep_equal(old, target.lines) then
						ok = pcall(vim.api.nvim_buf_set_lines, target.reg.buf, 0, -1, false, target.lines)
					end
					if not ok then
						u.notify(target.language .. ": replacement failed; target was not intentionally changed")
					end
					finish(op, target, ok and "succeeded" or "failed")
				end
			end
		end
	end

	function M.run(opts)
		opts = u.options(opts)
		u.check(session.status() == "active", "inactive", "Run requires an active workbench")
		local source = session.resolve(session.reference(vim.api.nvim_get_current_buf()))
		local text = require("rosetta.text").encode(vim.api.nvim_buf_get_lines(source.buf, 0, -1, false))
		if not text then
			u.fail("text", "Source must contain valid UTF-8 logical lines without CR or NUL")
		end
		---@cast text string
		if not text:find("%S") then
			u.callback(opts.on_complete, { noop = true })
			return { noop = true }
		end
		local execution, targets, excluded = deps.provider.capture(), {}, {}
		for _, slot in ipairs(session.slots()) do
			local reg = slot.registration
			if reg ~= source then
				if session.is_live(reg) and M.eligible(reg.buf) then
					local messages = require("rosetta.chat").messages(source.slot, slot, text)
					local request = execution.prepare(messages, text)
					targets[#targets + 1] =
						{ reg = reg, locale_epoch = reg.locale_epoch, language = slot.id, request = request }
				else
					excluded[#excluded + 1] = slot.id
				end
			end
		end
		u.check(#targets > 0, "targets", "No eligible loaded, modifiable targets with supported native undo")
		M.cancel()
		serial = serial + 1
		local op = {
			id = serial,
			source = source,
			source_locale_epoch = source.locale_epoch,
			targets = targets,
			execution = execution,
			model = execution.model,
			remaining = #targets,
			results = {},
			callback = opts.on_complete,
		}
		operation = op
		states[source] = {}
		for _, target in ipairs(targets) do
			states[target.reg] = { outcome = "running" }
		end
		if #excluded > 0 then
			u.notify("Excluded ineligible targets: " .. table.concat(excluded, ", "))
		end
		for _, target in ipairs(targets) do
			target.handle = execution.dispatch(target.request, function(response)
				if target.finished then
					return
				end
				if not current(op, target) then
					finish(op, target, "cancelled")
					return
				end
				local lines = not response.error
					and response.status
					and response.status >= 200
					and response.status < 300
					and require("rosetta.chat").response(response.body)
				if not lines then
					u.notify(
						target.language
							.. " / "
							.. op.model
							.. ": translation failed"
							.. (response.status and " (HTTP " .. response.status .. ")" or "")
					)
					finish(op, target, "failed")
					return
				end
				target.lines = lines
				state(target.reg).outcome = "waiting"
				M.deliver()
				deps.on_changed()
			end)
			target.request = nil
		end
		deps.on_changed()
		return { accepted = true, id = op.id, targets = #targets }
	end

	return M
end

return Translation
