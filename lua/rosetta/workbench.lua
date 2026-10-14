local u = require("rosetta.util")
local M = {}
local services

-- The composition root is lazy. Constructors only wire dependencies; activation
-- owns autocmd installation, buffers, checker startup and provider preparation.
local function get()
	if services then
		return services
	end
	local session = require("rosetta.session").new()
	local s = { session = session }
	local config = require("rosetta.config").get
	local function refresh()
		if s.presentation then
			s.presentation.request_refresh()
		end
	end
	s.provider = require("rosetta.provider").new({
		config = config,
		is_active = function()
			return session.is_alive() and session.status() == "active"
		end,
		on_changed = refresh,
		http = require("rosetta.transport").http,
		credentials = require("rosetta.credentials").read,
	})
	s.translation = require("rosetta.translation").new({
		session = session,
		provider = s.provider,
		on_changed = refresh,
		mode = function()
			return vim.api.nvim_get_mode().mode
		end,
	})
	s.checking = require("rosetta.checking").new({
		config = config,
		is_live = session.is_live,
		on_changed = refresh,
	})
	s.layout = require("rosetta.layout").new({
		config = config,
		slots = session.slots,
		is_live = session.is_live,
		is_alive = session.is_alive,
		on_changed = refresh,
	})
	s.presentation = require("rosetta.presentation").new({
		is_alive = session.is_alive,
		registration = function(win)
			local reg = session.lookup(vim.api.nvim_win_get_buf(win))
			return session.is_live(reg) and reg or nil
		end,
		native_available = function(reg)
			return s.checking.record(reg).native_available or false
		end,
		model = function(reg, win)
			return {
				name = reg.slot.definition.variants[reg.slot.variant].name,
				checking = s.checking.label(reg, win),
				translation = require("rosetta.view").translation(
					session.status(),
					s.provider.status(),
					s.translation.status(reg)
				),
			}
		end,
	})
	services = s
	return s
end

local function retire(s, reg)
	if s.session.lookup(reg.buf) ~= reg then
		return
	end
	s.translation.invalidate(reg)
	s.checking.detach(reg)
	s.session.retire(reg)
	if vim.api.nvim_buf_is_valid(reg.buf) then
		vim.b[reg.buf].rosetta_owned = nil
	end
	s.presentation.request_refresh()
end

local function attach_checker(s, reg, preserve_profile)
	local ok = pcall(function()
		vim.bo[reg.buf].filetype = "markdown"
		s.checking.attach(reg, preserve_profile)
	end)
	if not ok then
		s.checking.failed(reg)
		u.notify(reg.slot.id .. ": checker setup failed; editing remains available")
	end
end

local function initialize(s)
	if s.initialized then
		return
	end
	local session = s.session
	require("rosetta.lifecycle").start({
		disposing = function(buf, disposing)
			local reg = session.lookup(buf)
			-- Rename also emits delete events. Classify after the event sequence.
			vim.schedule(function()
				if not session.is_alive() then
					return
				end
				local valid = vim.api.nvim_buf_is_valid(buf)
				if reg and session.lookup(buf) == reg and not session.is_live(reg) then
					retire(s, reg)
				end
				if disposing and not valid then
					require("rosetta.files").cleanup(buf)
				end
			end)
		end,
		renamed = function(buf)
			local reg = session.lookup(buf)
			if session.is_live(reg) then
				session.renamed(reg)
				attach_checker(s, reg, true)
				s.presentation.request_refresh()
			end
		end,
		filetype = function(buf)
			if session.is_live(session.lookup(buf)) and vim.bo[buf].filetype ~= "markdown" then
				vim.bo[buf].filetype = "markdown"
			end
		end,
		changed = function(buf)
			local reg = session.lookup(buf)
			if session.is_live(reg) then
				s.checking.inspect(reg)
				s.presentation.request_refresh()
			end
		end,
		refresh = s.presentation.request_refresh,
		resize = s.layout.resize,
		deliver = s.translation.deliver,
		shutdown = function()
			session.shutdown()
			s.provider.stop()
			s.translation.cancel()
			require("rosetta.process").shutdown()
			require("rosetta.files").cleanup(nil, true)
		end,
	})
	s.initialized = true
end

local function allocate(s, slot)
	local buf = vim.api.nvim_create_buf(false, false)
	local ok, reg = pcall(function()
		local path = require("rosetta.files").reserve(buf, "text." .. slot.id .. ".md")
		vim.b[buf].rosetta_owned = true
		vim.bo[buf].spelllang = ""
		vim.bo[buf].bufhidden = "hide"
		vim.api.nvim_buf_set_name(buf, path)
		return s.session.create(buf, slot)
	end)
	if not ok then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		require("rosetta.files").cleanup(buf)
		u.fail("allocation", "Could not allocate a workbench buffer")
	end
	return reg
end

local function prepare(s, requested)
	local previous = s.session.slots()
	local plan = { old = {}, fresh = {}, staged = {}, variants = {}, changed = #requested ~= #previous }
	for _, slot in ipairs(previous) do
		plan.old[slot.id] = slot
	end
	local ok = pcall(function()
		require("rosetta.files").directory()
		for i, slot in ipairs(requested) do
			local old = plan.old[slot.id]
			if old and s.session.is_live(old.registration) then
				slot.registration = old.registration
				plan.variants[slot.registration] = old.variant ~= slot.variant
			else
				slot.registration = allocate(s, slot)
				plan.staged[#plan.staged + 1] = slot.registration
				plan.fresh[slot.registration] = true
			end
			if not previous[i] or previous[i].id ~= slot.id then
				plan.changed = true
			end
		end
	end)
	if not ok then
		for _, reg in ipairs(plan.staged) do
			pcall(vim.api.nvim_buf_delete, reg.buf, { force = true })
			require("rosetta.files").cleanup(reg.buf)
		end
		require("rosetta.files").prune()
		u.fail("allocation", "Startup allocation failed; previous registrations were preserved")
	end
	return plan
end

local function commit(s, requested, plan)
	if plan.changed then
		s.translation.cancel()
	end
	local retained = {}
	for _, slot in ipairs(requested) do
		retained[slot.registration] = true
	end
	for _, slot in pairs(plan.old) do
		if slot.registration and not retained[slot.registration] then
			retire(s, slot.registration)
		end
	end
	for reg, changed in pairs(plan.variants) do
		if changed then
			s.translation.invalidate(reg)
			s.session.locale_changed(reg)
			s.translation.changed(reg, false)
		end
	end
	s.session.commit(requested)
	for _, slot in ipairs(requested) do
		local reg = slot.registration
		vim.bo[reg.buf].buflisted = true
		if plan.fresh[reg] then
			require("rosetta.lifecycle").watch(reg.buf, function()
				-- Remember actual detachment even if user code immediately reloads it.
				s.session.detached(reg)
				vim.schedule(function()
					if s.session.is_alive() then
						retire(s, reg)
					end
				end)
			end)
		end
		if plan.fresh[reg] or plan.variants[reg] then
			attach_checker(s, reg)
		end
	end
end

local function reconcile(s, requested, explicit_layout, opts)
	opts = u.options(opts)
	u.check(vim.fn.has("nvim-0.12.5") == 1, "version", "Rosetta requires Neovim 0.12.5 or newer")
	u.check(s.session.is_alive(), "shutdown", "Neovim is shutting down")
	initialize(s)
	local plan = prepare(s, requested)
	commit(s, requested, plan)
	local activating = s.session.status() ~= "active"
	s.session.activate()
	local displayed, problem = u.try(s.layout.restore, explicit_layout)
	if not displayed and problem then
		u.notify("Partial display; run :Rosetta layout after adjusting windows")
	end
	if activating then
		s.provider.activate(opts)
	else
		s.provider.observe(opts.on_complete)
	end
	s.presentation.request_refresh()
	return {
		accepted = true,
		tab = s.layout.tab(),
		languages = vim.tbl_map(function(slot)
			return slot.id
		end, requested),
	}
end

function M.start(inputs, opts)
	local config = require("rosetta.config").get()
	local s = get()
	local requested = require("rosetta.registry").resolve_list(
		config.resolver,
		inputs or config.languages,
		s.session.slots(),
		s.session.remembered()
	)
	return reconcile(s, requested, false, opts)
end

function M.restore(opts)
	local s = get()
	if #s.session.slots() == 0 then
		return M.start(nil, opts)
	end
	local slots = {}
	for _, slot in ipairs(s.session.slots()) do
		slots[#slots + 1] = { id = slot.id, definition = slot.definition, variant = slot.variant }
	end
	return reconcile(s, slots, true, opts)
end

function M.stop()
	if not services or services.session.status() == "unconfigured" then
		return true
	end
	services.session.stop()
	services.provider.stop()
	services.translation.cancel()
	services.presentation.request_refresh()
	return true
end

local function change(s, reg, resolved)
	if reg.slot.id == resolved.id and reg.slot.variant == resolved.variant then
		return true
	end
	local identity = reg.slot.id ~= resolved.id
	if identity then
		s.translation.cancel()
	else
		s.translation.invalidate(reg)
	end
	s.session.change(reg, resolved)
	s.translation.changed(reg, identity)
	attach_checker(s, reg)
	s.presentation.request_refresh()
	return true
end

function M.reassign(ref, input)
	local s = get()
	local reg = s.session.resolve(ref)
	local registry = require("rosetta.config").get().resolver
	local entry = type(input) == "string" and registry.inputs[input:lower()]
	local resolved = require("rosetta.registry").resolve(
		registry,
		input,
		entry and entry.id == reg.slot.id and reg.slot or nil,
		s.session.remembered()
	)
	for _, slot in ipairs(s.session.slots()) do
		u.check(
			slot == reg.slot or slot.id ~= resolved.id,
			"duplicate",
			"Identity already occupies another requested slot"
		)
	end
	return change(s, reg, resolved)
end

function M.reference(buf)
	return get().session.reference(buf)
end
function M.run(opts)
	return get().translation.run(opts)
end

function M.reconnect(opts)
	opts = u.options(opts)
	local s = get()
	u.check(s.session.status() == "active", "inactive", "Reconnect requires an active workbench")
	s.translation.cancel()
	s.provider.activate(opts)
	return { accepted = true, generation = s.provider.status().generation }
end

function M.model(opts)
	opts = u.options(opts)
	local entries, select = get().provider.model_choices()
	return require("rosetta.pickers").open("Rosetta model", entries, function(entry)
		return entry
	end, function(model)
		return select(model, opts.on_complete)
	end)
end

function M.variant(ref, opts)
	opts = u.options(opts)
	local s = get()
	ref = ref or s.session.reference()
	local reg = s.session.resolve(ref)
	local epoch, definition = reg.locale_epoch, reg.slot.definition
	local entries = vim.tbl_keys(definition.variants)
	table.sort(entries)
	return require("rosetta.pickers").open("Rosetta variant", entries, function(id)
		return definition.variants[id].name .. " (" .. id .. ")"
	end, function(variant)
		local current = s.session.resolve(ref)
		u.check(current.locale_epoch == epoch, "stale_picker", "Variant picker is stale; open it again")
		change(s, current, { id = definition.id, definition = definition, variant = variant })
		u.callback(opts.on_complete, { variant = variant })
		return true
	end)
end

function M.status()
	local s = get()
	local result = { state = s.session.status(), languages = {}, provider = s.provider.status() }
	for _, slot in ipairs(s.session.slots()) do
		local reg = slot.registration
		local translation = reg and s.translation.status(reg) or {}
		result.languages[#result.languages + 1] = {
			id = slot.id,
			variant = slot.variant,
			buffer = s.session.is_live(reg) and reg.buf or nil,
			pending = require("rosetta.view").pending(translation.pending),
			outcome = translation.outcome,
		}
	end
	return result
end

return M
