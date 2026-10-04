local M = {}

function M.profile()
	return {
		context = 100000,
		completion = 10000,
		overhead = 0,
		min_output = 10,
		expansion = 1,
		reasoning_tokens = 0,
		reasoning_shares_completion = false,
		budget_field = "max_tokens",
		probe_tokens = 10,
		estimate = function(text)
			return #text
		end,
		estimator_note = "Test byte upper bound",
	}
end

function M.response(text)
	return {
		status = 200,
		body = vim.json.encode({
			choices = {
				{ message = { role = "assistant", content = text }, finish_reason = "stop" },
			},
		}),
	}
end

function M.provider()
	local f = { active = true, requests = {}, credentials = {}, events = {} }
	f.config = require("rosetta.config").candidate({
		provider = {
			base_url = "https://example.invalid/v1",
			model = "first",
			profiles = { first = M.profile(), second = M.profile() },
		},
	})
	f.provider = require("rosetta.provider").new({
		config = function()
			return f.config
		end,
		is_active = function()
			return f.active
		end,
		on_changed = function() end,
		credentials = function(_, callback)
			local request = { reply = callback }
			f.credentials[#f.credentials + 1] = request
			return {
				cancel = function()
					request.cancelled = true
				end,
			}
		end,
		http = function(_, method, route, body, callback)
			local request = { method = method, route = route, body = body, reply = callback }
			f.requests[#f.requests + 1] = request
			return {
				cancel = function()
					request.cancelled = true
				end,
			}
		end,
	})
	function f.activate()
		f.provider.activate({
			on_complete = function(value)
				f.events[#f.events + 1] = value
			end,
		})
		f.credentials[#f.credentials].reply("fixture-key")
	end
	function f.ready()
		f.activate()
		f.requests[#f.requests - 1].reply({
			status = 200,
			body = vim.json.encode({ data = { { id = "first" }, { id = "second" } } }),
		})
		f.requests[#f.requests].reply(M.response("Probe succeeded"))
		assert(f.provider.status().ready)
	end
	return f
end

function M.translation()
	local f = M.provider()
	f.ready()
	f.session = require("rosetta.session").new()
	local slots = require("rosetta.registry").resolve_list(f.config.resolver, { "en", "de", "fr" })
	f.registrations = {}
	for _, slot in ipairs(slots) do
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { slot.id == "en" and "Source text" or "Original target" })
		slot.registration = f.session.create(buf, slot)
		f.registrations[#f.registrations + 1] = slot.registration
	end
	f.session.commit(slots)
	f.session.activate()
	vim.api.nvim_set_current_buf(f.registrations[1].buf)
	f.mode, f.completed = "n", {}
	f.translation = require("rosetta.translation").new({
		session = f.session,
		provider = f.provider,
		on_changed = function() end,
		mode = function()
			return f.mode
		end,
	})
	function f.run()
		return f.translation.run({
			on_complete = function(value)
				f.completed[#f.completed + 1] = value
			end,
		})
	end
	return f
end

return M
