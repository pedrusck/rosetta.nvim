local M = {}
local pending = { language_changed = "Language changed", variant_changed = "Variant changed" }

function M.pending(reason)
	return pending[reason]
end

function M.translation(session_status, provider, translation)
	if session_status == "stopped" then
		return "Stopped"
	end
	if not provider.ready then
		return provider.label
	end
	if translation.outcome == "running" then
		return "Translating"
	end
	if translation.outcome == "waiting" then
		return "Waiting for Normal mode"
	end
	if translation.outcome == "failed" then
		return "Request error"
	end
	if translation.pending then
		return pending[translation.pending]
	end
	return translation.outcome == "succeeded" and "Success" or "Ready"
end

function M.winbar(model)
	return table.concat({ model.name, model.checking, model.translation }, " | "):gsub("%%", "%%%%")
end

return M
