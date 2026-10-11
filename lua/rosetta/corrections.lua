local Corrections = {}

function Corrections.new(deps)
	local M = {}

	function M.snapshot(reg, position, encoding)
		if not deps.is_live(reg) then
			return nil
		end
		if
			type(position) ~= "table"
			or type(position.line) ~= "number"
			or position.line < 0
			or position.line % 1 ~= 0
			or type(position.character) ~= "number"
			or position.character < 0
			or position.character % 1 ~= 0
		then
			return nil
		end
		local line = vim.api.nvim_buf_get_lines(reg.buf, position.line, position.line + 1, false)[1]
		if not line or not require("rosetta.text").valid(line) then
			return nil
		end
		local ok, byte = pcall(vim.str_byteindex, line, encoding, position.character, true)
		if not ok or byte > #line then
			return nil
		end
		local checker = deps.checker_record(reg)
		return {
			reg = reg,
			checker = checker,
			tick = vim.api.nvim_buf_get_changedtick(reg.buf),
			locale_epoch = reg.locale_epoch,
			uri_epoch = reg.uri_epoch,
			checker_epoch = checker.checker_epoch,
			uri = vim.uri_from_bufnr(reg.buf),
			line = line,
			row = position.line,
			byte = byte,
			encoding = encoding,
		}
	end

	function M.current(s)
		local reg = s.reg
		return deps.is_live(reg)
			and reg.locale_epoch == s.locale_epoch
			and reg.uri_epoch == s.uri_epoch
			and deps.checker_record(reg).checker_epoch == s.checker_epoch
			and vim.api.nvim_buf_get_changedtick(reg.buf) == s.tick
			and vim.uri_from_bufnr(reg.buf) == s.uri
	end

	local function position(line, byte, row, encoding)
		return { line = row, character = vim.str_utfindex(line, encoding, byte, true) }
	end

	local function item(s, first, last, replacement)
		return {
			label = replacement,
			filterText = s.line:sub(first + 1, last),
			kind = vim.lsp.protocol.CompletionItemKind.Text,
			textEdit = {
				range = {
					start = position(s.line, first, s.row, s.encoding),
					["end"] = position(s.line, last, s.row, s.encoding),
				},
				newText = replacement,
			},
		}
	end

	function M.native(s)
		local reg, checker, bounds = s.reg, s.checker, s.checker.correction_profile
		if
			not checker.native_available
			or #s.line > bounds.max_line_bytes
			or vim.bo[reg.buf].spelllang ~= checker.native_last
		then
			return {}
		end
		local window
		for _, win in ipairs(vim.fn.win_findbuf(reg.buf)) do
			if vim.wo[win].spell then
				window = win
				break
			end
		end
		if not window then
			return {}
		end
		-- Arbitrary user expr/file suggestion sources cannot be bounded safely. Until
		-- verified consumers ship, the backend accepts only explicitly bounded native
		-- methods and never changes the user's global spelling policy.
		local timeout = vim.o.spellsuggest:match("^timeout:(%d+),[a-z]+$")
		local method = vim.o.spellsuggest:match(",([a-z]+)$")
		if
			not timeout
			or tonumber(timeout) > bounds.timeout_ms
			or not ({ fast = true, best = true, double = true })[method]
		then
			return {}
		end
		local result = {}
		vim.api.nvim_win_call(window, function()
			local span
			for _, found in ipairs(vim.spell.check(s.line)) do
				local first, last = found[3] - 1, found[3] - 1 + #found[1]
				if first <= s.byte and last >= s.byte then
					if not span or s.byte < last then
						span = { first, last, found[1], found[2] }
					end
					if s.byte < last then
						break
					end
				end
			end
			if not span or #span[3] > bounds.max_word_bytes then
				return
			end
			local view = vim.fn.winsaveview()
			local ok, suggestions = pcall(function()
				vim.api.nvim_win_set_cursor(window, { s.row + 1, span[1] })
				local bad = vim.fn.spellbadword()
				local cursor = vim.api.nvim_win_get_cursor(window)
				if bad[1] ~= span[3] or cursor[1] ~= s.row + 1 or cursor[2] ~= span[1] then
					return {}
				end
				return vim.fn.spellsuggest(span[3], bounds.max_suggestions, span[4] == "caps")
			end)
			vim.fn.winrestview(view)
			if not ok then
				return
			end
			for _, replacement in ipairs(suggestions) do
				if
					#replacement <= bounds.max_bytes
					and require("rosetta.text").valid(replacement)
					and not replacement:find("\n", 1, true)
				then
					result[#result + 1] = item(s, span[1], span[2], replacement)
				end
			end
		end)
		return result
	end

	function M.action(s, action, encoding)
		if type(action) ~= "table" or action.command or action.disabled or type(action.edit) ~= "table" then
			return nil
		end
		local workspace = action.edit
		local edits
		if workspace.changeAnnotations then
			return nil
		end
		if workspace.changes and workspace.documentChanges then
			return nil
		end
		if workspace.changes then
			if type(workspace.changes) ~= "table" or vim.tbl_count(workspace.changes) ~= 1 then
				return nil
			end
			edits = workspace.changes[s.uri]
		elseif type(workspace.documentChanges) == "table" and #workspace.documentChanges == 1 then
			local change = workspace.documentChanges[1]
			if change.kind or type(change.textDocument) ~= "table" or change.textDocument.uri ~= s.uri then
				return nil
			end
			local version = change.textDocument.version
			if
				version ~= nil
				and version ~= vim.NIL
				and (not s.checker.sent_document or version ~= s.checker.sent_document.version)
			then
				return nil
			end
			edits = change.edits
		end
		if type(edits) ~= "table" or #edits ~= 1 then
			return nil
		end
		local edit = edits[1]
		if type(edit) ~= "table" or edit.annotationId or type(edit.range) ~= "table" then
			return nil
		end
		local first, last = edit.range.start, edit.range["end"]
		if
			type(first) ~= "table"
			or type(last) ~= "table"
			or first.line ~= s.row
			or last.line ~= s.row
			or type(first.character) ~= "number"
			or type(last.character) ~= "number"
		then
			return nil
		end
		local text = edit.newText
		if
			not require("rosetta.text").valid(text)
			or text:find("\n", 1, true)
			or #text > s.checker.correction_profile.max_bytes
		then
			return nil
		end
		local ok, a, b = pcall(function()
			return vim.str_byteindex(s.line, encoding, first.character, true),
				vim.str_byteindex(s.line, encoding, last.character, true)
		end)
		if not ok or a >= b or a > s.byte or b < s.byte or b > #s.line then
			return nil
		end
		return item(s, a, b, text)
	end

	function M.collect(s, callback)
		local bounds, cancelled, completed = s.checker.correction_profile, false, false
		local items, seen, bytes, requests = {}, {}, 0, {}
		local function add(candidate)
			if not candidate or #items >= bounds.max_suggestions then
				return
			end
			local edit = candidate.textEdit
			local key = vim.json.encode({ edit.range.start, edit.range["end"], edit.newText })
			if not seen[key] and bytes + #key <= bounds.max_bytes then
				seen[key], bytes = true, bytes + #key
				items[#items + 1] = candidate
			end
		end
		for _, candidate in ipairs(M.native(s)) do
			add(candidate)
		end
		local client = s.checker.client and vim.lsp.get_client_by_id(s.checker.client)
		local timer
		local function cancel_requests()
			if timer and not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			if client then
				for _, id in ipairs(requests) do
					client:cancel_request(id)
				end
			end
		end
		local function finish()
			if completed or cancelled then
				return
			end
			completed = true
			cancel_requests()
			vim.schedule(function()
				if not cancelled then
					callback(M.current(s) and items or {})
				end
			end)
		end
		local handle = {
			cancel = function()
				cancelled = true
				cancel_requests()
			end,
		}
		local diagnostics = s.checker.diagnostics
		if
			not client
			or not diagnostics
			or diagnostics.context.tick ~= s.tick
			or diagnostics.context.locale_epoch ~= s.locale_epoch
			or diagnostics.context.uri_epoch ~= s.uri_epoch
			or diagnostics.context.epoch ~= s.checker_epoch
		then
			finish()
			return handle
		end
		local relevant = {}
		local encoding = client.offset_encoding
		local request_position = position(s.line, s.byte, s.row, encoding)
		for i = 1, math.min(#diagnostics.items, bounds.max_actions) do
			local diagnostic = diagnostics.items[i]
			local r = diagnostic.range
			if
				r
				and r.start.line == s.row
				and r["end"].line == s.row
				and r.start.character <= request_position.character
				and r["end"].character >= request_position.character
			then
				relevant[#relevant + 1] = diagnostic
			end
		end
		if #relevant == 0 then
			finish()
			return handle
		end
		timer = vim.uv.new_timer()
		if not timer then
			finish()
			return handle
		end
		timer:start(bounds.action_timeout_ms, 0, vim.schedule_wrap(finish))
		local ok, id = client:request("textDocument/codeAction", {
			textDocument = { uri = s.uri },
			range = { start = request_position, ["end"] = request_position },
			context = { diagnostics = relevant, only = { "quickfix" } },
		}, function(err, actions)
			if completed or cancelled then
				return
			end
			if err or type(actions) ~= "table" or not M.current(s) then
				finish()
				return
			end
			local remaining = 0
			for i = 1, math.min(#actions, bounds.max_actions) do
				local action = actions[i]
				if type(action) == "table" and not action.command and not action.disabled then
					if action.edit then
						add(M.action(s, action, encoding))
					elseif action.data and client:supports_method("codeAction/resolve") then
						remaining = remaining + 1
						local sent, resolve_id = client:request(
							"codeAction/resolve",
							action,
							function(resolve_error, resolved)
								if completed or cancelled then
									return
								end
								if not resolve_error and M.current(s) then
									add(M.action(s, resolved, encoding))
								end
								remaining = remaining - 1
								if remaining == 0 then
									finish()
								end
							end,
							s.reg.buf
						)
						if sent then
							requests[#requests + 1] = resolve_id
						else
							remaining = remaining - 1
						end
					end
				end
			end
			if remaining == 0 then
				finish()
			end
		end, s.reg.buf)
		if ok then
			requests[#requests + 1] = id
		else
			finish()
		end
		return handle
	end

	return M
end

return Corrections
