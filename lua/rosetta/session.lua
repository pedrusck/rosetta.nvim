local u = require("rosetta.util")
local M = {}

---Create a side-effect-free registration store. Only this store mutates membership.
function M.new()
	local state, alive = "unconfigured", true
	local slots, by_buf, handles, remembered = {}, {}, {}, {}
	local serial = 0
	local self = {}

	function self.is_alive()
		return alive
	end
	function self.status()
		return state
	end
	function self.activate()
		state = "active"
	end
	function self.stop()
		if state ~= "unconfigured" then
			state = "stopped"
		end
	end
	function self.shutdown()
		alive = false
	end
	-- Borrowed, read-only to consumers. Changes go through commit/change/retire.
	function self.slots()
		return slots
	end
	function self.remembered()
		return remembered
	end
	function self.lookup(buf)
		return by_buf[buf]
	end
	function self.is_live(reg)
		return reg ~= nil
			and not reg.detached
			and alive
			and by_buf[reg.buf] == reg
			and vim.api.nvim_buf_is_valid(reg.buf)
			and vim.api.nvim_buf_is_loaded(reg.buf)
			and vim.bo[reg.buf].buflisted
	end
	function self.reference(buf)
		if buf == nil or buf == 0 then
			buf = vim.api.nvim_get_current_buf()
		end
		local reg = by_buf[buf]
		u.check(self.is_live(reg), "registration", "A registered loaded buffer is required")
		return reg.ref
	end
	function self.resolve(ref)
		local reg = handles[ref]
		u.check(self.is_live(reg), "registration", "This registration is no longer current")
		return reg
	end
	function self.find_uri(uri)
		for _, reg in pairs(by_buf) do
			if self.is_live(reg) and vim.uri_from_bufnr(reg.buf) == uri then
				return reg
			end
		end
	end
	function self.create(buf, slot)
		serial = serial + 1
		return {
			buf = buf,
			ref = {},
			registration_id = serial,
			slot = slot,
			locale_epoch = 1,
			uri_epoch = 1,
		}
	end
	function self.commit(requested)
		slots = requested
		for _, slot in ipairs(slots) do
			local reg = slot.registration
			reg.slot = slot
			handles[reg.ref], by_buf[reg.buf] = reg, reg
			remembered[slot.id] = slot.variant
		end
	end
	function self.retire(reg)
		if by_buf[reg.buf] ~= reg then
			return false
		end
		handles[reg.ref], by_buf[reg.buf] = nil, nil
		reg.slot.registration = nil
		return true
	end
	function self.change(reg, resolved)
		for key, value in pairs(resolved) do
			reg.slot[key] = value
		end
		reg.locale_epoch = reg.locale_epoch + 1
		remembered[reg.slot.id] = reg.slot.variant
	end
	function self.locale_changed(reg)
		reg.locale_epoch = reg.locale_epoch + 1
	end
	function self.renamed(reg)
		reg.uri_epoch = reg.uri_epoch + 1
	end
	function self.detached(reg)
		reg.detached = true
	end
	return self
end

return M
