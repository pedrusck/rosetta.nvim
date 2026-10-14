local M = {}

-- All editor event wiring lives here; the coordinator supplies behavior.
function M.start(callbacks)
	local group = vim.api.nvim_create_augroup("RosettaWorkbench", { clear = true })
	local function on(events, callback, options)
		vim.api.nvim_create_autocmd(
			events,
			vim.tbl_extend("force", {
				group = group,
				callback = callback,
				desc = "Rosetta workbench lifecycle",
			}, options or {})
		)
	end
	on({ "BufUnload", "BufDelete", "BufWipeout" }, function(ev)
		callbacks.disposing(ev.buf, ev.event == "BufWipeout")
	end)
	on("BufFilePost", function(ev)
		callbacks.renamed(ev.buf)
	end)
	on({ "BufWinEnter", "WinEnter", "WinClosed", "BufEnter", "LspAttach", "LspDetach" }, callbacks.refresh)
	on("OptionSet", callbacks.refresh, {
		pattern = { "spell", "spelllang", "winbar", "modifiable", "undolevels", "cpoptions" },
	})
	on("FileType", function(ev)
		callbacks.filetype(ev.buf)
	end)
	on("VimResized", callbacks.resize)
	on({ "TextChanged", "TextChangedI" }, function(ev)
		callbacks.changed(ev.buf)
	end)
	on("ModeChanged", function()
		vim.schedule(callbacks.deliver)
	end, { pattern = "*:n" })
	on("VimLeavePre", callbacks.shutdown)
end

function M.watch(buf, detached)
	vim.api.nvim_buf_attach(buf, false, { on_detach = detached })
end

return M
