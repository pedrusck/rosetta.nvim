local u = require("rosetta.util")
local Checking = {}

local management = {
	["_ltex.addToDictionary"] = true,
	["_ltex.disableRules"] = true,
	["_ltex.hideFalsePositives"] = true,
}

function Checking.safe_actions(actions)
	if type(actions) ~= "table" then
		return actions
	end
	return vim.tbl_filter(function(action)
		if type(action) ~= "table" then
			return false
		end
		local command = type(action.command) == "table" and action.command.command or action.command
		return not management[command]
	end, actions)
end

function Checking.new(deps)
	local M = {}
	local records = setmetatable({}, { __mode = "k" })

	-- Checker records belong to this service, never to the registration store.
	function M.record(reg)
		if not records[reg] then
			records[reg] = { checker_epoch = 0 }
		end
		return records[reg]
	end

	function M.failed(reg)
		M.record(reg).checker_note = "Checker setup failed"
	end

	function M.detach(reg, preserve_native)
		local record = M.record(reg)
		record.checker_epoch = record.checker_epoch + 1
		if record.client then
			local client = vim.lsp.get_client_by_id(record.client)
			if client then
				pcall(vim.lsp.buf_detach_client, reg.buf, client.id)
				client:stop(true)
			end
		end
		record.client, record.ltex_active = nil, false
		record.diagnostics, record.sent_document = nil, nil
		if
			not preserve_native
			and record.native_original ~= nil
			and vim.api.nvim_buf_is_valid(reg.buf)
			and vim.bo[reg.buf].spelllang == record.native_last
		then
			vim.bo[reg.buf].spelllang = record.native_original
		end
	end

	function M.attach(reg, preserve_profile)
		M.detach(reg, preserve_profile)
		local record = M.record(reg)
		local config = deps.config()
		if not preserve_profile then
			record.checker_profile = vim.deepcopy(config.checker)
			record.correction_profile = vim.deepcopy(config.corrections)
		end
		local variant = reg.slot.definition.variants[reg.slot.variant]
		if not preserve_profile then
			record.native_original = vim.bo[reg.buf].spelllang
			record.native_available = require("rosetta.spell").available(variant.spell)
			record.native_last = record.native_available and variant.spell or ""
			vim.bo[reg.buf].spelllang = record.native_last
		end
		record.ltex_active, record.checker_note = false, nil
		M.inspect(reg)
		local profile = record.checker_profile
		if not profile.enabled or not variant.ltex then
			return
		end
		if not profile.locales[variant.ltex] or (variant.hosted_only and not profile.hosted) then
			record.checker_note = "LTeX+ locale unverified"
			return
		end
		if vim.fn.executable(profile.cmd[1]) ~= 1 then
			record.checker_note = "LTeX+ unavailable"
			return
		end
		local settings = vim.tbl_deep_extend(
			"force",
			{ ltex = { enabled = { "markdown" }, checkFrequency = "edit" } },
			profile.settings
		)
		settings.ltex.language = variant.ltex
		if settings.ltex.checkFrequency ~= "edit" or not vim.tbl_contains(settings.ltex.enabled, "markdown") then
			record.checker_note = "LTeX+ profile must enable edit-time Markdown checking"
			return
		end
		local epoch = record.checker_epoch
		local function current()
			return deps.is_live(reg) and record.checker_epoch == epoch
		end
		record.client = vim.lsp.start({
			name = "rosetta-ltex-" .. reg.registration_id .. "-" .. epoch,
			cmd = profile.cmd,
			root_dir = require("rosetta.files").directory(),
			settings = settings,
			flags = { debounce_text_changes = profile.debounce_ms },
			on_init = function(client)
				local request = client.request
				client.request = function(self, method, params, callback, buf)
					if method == "textDocument/codeAction" and callback then
						local original = callback
						callback = function(err, result, context, handler_config)
							return original(err, Checking.safe_actions(result), context, handler_config)
						end
					end
					return request(self, method, params, callback, buf)
				end
				-- Correlate optional diagnostic versions with actual outbound document
				-- notifications. Never label diagnostics using their arrival changedtick.
				local notify = client.notify
				client.notify = function(self, method, params)
					if current() and (method == "textDocument/didOpen" or method == "textDocument/didChange") then
						record.sent_document = {
							version = params.textDocument.version,
							uri = params.textDocument.uri,
							tick = vim.api.nvim_buf_get_changedtick(reg.buf),
							epoch = epoch,
							locale_epoch = reg.locale_epoch,
							uri_epoch = reg.uri_epoch,
						}
					end
					return notify(self, method, params)
				end
			end,
			on_attach = function(client)
				if not current() then
					client:stop(true)
					return
				end
				record.ltex_active = true
				M.inspect(reg)
				deps.on_changed()
			end,
			on_exit = function()
				vim.schedule(function()
					if current() then
						record.ltex_active = false
						record.checker_note = "LTeX+ stopped"
						deps.on_changed()
					end
				end)
			end,
			handlers = {
				["textDocument/publishDiagnostics"] = function(err, params, ctx, handler_config)
					if not current() then
						return
					end
					local sent = record.sent_document
					if
						not err
						and sent
						and params.version ~= nil
						and params.version == sent.version
						and params.uri == sent.uri
						and sent.tick == vim.api.nvim_buf_get_changedtick(reg.buf)
						and sent.locale_epoch == reg.locale_epoch
						and sent.uri_epoch == reg.uri_epoch
					then
						record.diagnostics = { items = params.diagnostics, context = vim.deepcopy(sent) }
					else
						record.diagnostics = nil
					end
					return vim.lsp.handlers["textDocument/publishDiagnostics"](err, params, ctx, handler_config)
				end,
			},
			commands = {
				["_ltex.addToDictionary"] = function()
					u.notify("LTeX+ persistence requires a verified external integration")
				end,
				["_ltex.disableRules"] = function()
					u.notify("LTeX+ persistence requires a verified external integration")
				end,
				["_ltex.hideFalsePositives"] = function()
					u.notify("LTeX+ persistence requires a verified external integration")
				end,
			},
		}, {
			bufnr = reg.buf,
			reuse_client = function()
				return false
			end,
		})
		if not record.client then
			record.checker_note = "LTeX+ failed to start"
		end
	end

	function M.inspect(reg)
		local record = M.record(reg)
		if not record.checker_profile or not record.checker_profile.enabled then
			return
		end
		local tick = vim.api.nvim_buf_get_changedtick(reg.buf)
		if record.directive_tick ~= tick then
			record.directive_tick, record.directive_mismatch = tick, false
			local count = vim.api.nvim_buf_line_count(reg.buf)
			-- Avoid unbounded status-line work. Large documents with unverified
			-- directive semantics are labelled pending instead of falsely active.
			if count > 10000 then
				record.directive_mismatch = true
			else
				local bytes = 0
				for first = 0, count - 1, 128 do
					for _, line in
						ipairs(vim.api.nvim_buf_get_lines(reg.buf, first, math.min(first + 128, count), false))
					do
						bytes = bytes + #line
						if
							bytes > 524288
							or (line:lower():find("ltex", 1, true) and line:lower():find("language", 1, true))
						then
							record.directive_mismatch = true
							break
						end
					end
					if record.directive_mismatch then
						break
					end
				end
			end
		end
	end

	function M.label(reg, win)
		local record = M.record(reg)
		local variant = reg.slot.definition.variants[reg.slot.variant]
		local native = record.native_available and vim.bo[reg.buf].spelllang == variant.spell and vim.wo[win].spell
		local client = record.client and vim.lsp.get_client_by_id(record.client)
		local ltex = record.ltex_active and client and client.initialized and not client:is_stopped()
		local mismatch = vim.bo[reg.buf].spelllang ~= record.native_last
		if client and vim.tbl_get(client.settings, "ltex", "language") ~= variant.ltex then
			mismatch = true
		end
		if
			ltex and (record.directive_tick ~= vim.api.nvim_buf_get_changedtick(reg.buf) or record.directive_mismatch)
		then
			return "LTeX+ document locale unverified"
		end
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = reg.buf })) do
			if client.id ~= record.client and client.name:lower():find("ltex", 1, true) then
				mismatch = true
			end
		end
		if mismatch then
			return "Checking mismatch"
		end
		local label = native and (ltex and "Spell + LTeX+" or "Spell") or (ltex and "LTeX+" or "No checking")
		if record.native_available and not vim.wo[win].spell then
			label = label .. " / Spell disabled"
		end
		if record.checker_note then
			label = label .. " / " .. record.checker_note
		elseif record.client and not ltex then
			label = label .. " / LTeX+ pending"
		end
		return label
	end

	return M
end

return Checking
