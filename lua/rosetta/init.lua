local M = {}

---@class rosetta.Error
---@field code string Stable error category; messages omit raw credentials/process output.
---@field message string

---@class rosetta.Options
---@field on_complete? fun(result: rosetta.CompletionResult) Scheduled once for accepted work, including cancellation.

---@class rosetta.Registration
---Opaque handle. Retain it instead of a buffer number for asynchronous calls.

local function call(module, method, ...)
	return require("rosetta.util").try_at(module .. "." .. method, function(...)
		return require("rosetta." .. module)[method](...)
	end, ...)
end

---@param opts? table Replacement overrides; does not activate the workbench.
---@return boolean? success
---@return rosetta.Error? error
function M.configure(opts)
	return call("config", "configure", opts)
end
---@param languages? string[] Omitted means configured defaults, not the remembered list.
---@param opts? rosetta.Options
---@return rosetta.StartReceipt? receipt
---@return rosetta.Error? error
function M.start(languages, opts)
	return call("workbench", "start", languages, opts)
end
---@param opts? rosetta.Options
---@return rosetta.RunReceipt|rosetta.Noop|nil receipt
---@return rosetta.Error? error
function M.run(opts)
	return call("workbench", "run", opts)
end
---@return boolean? success
---@return rosetta.Error? error
function M.stop()
	return call("workbench", "stop")
end
---@param opts? rosetta.Options
---@return rosetta.StartReceipt? receipt
---@return rosetta.Error? error
function M.layout(opts)
	return call("workbench", "restore", opts)
end
---@param opts? rosetta.Options
---@return rosetta.ProviderReceipt? receipt
---@return rosetta.Error? error
function M.reconnect(opts)
	return call("workbench", "reconnect", opts)
end
---@param opts? rosetta.Options
---@return rosetta.PickerReceipt? receipt
---@return rosetta.Error? error
function M.model(opts)
	return call("workbench", "model", opts)
end
---@param registration? rosetta.Registration
---@param opts? rosetta.Options
---@return rosetta.PickerReceipt? receipt
---@return rosetta.Error? error
function M.variant(registration, opts)
	return call("workbench", "variant", registration, opts)
end
---@param bufnr? integer Omitted or zero means current buffer.
---@return rosetta.Registration? registration
---@return rosetta.Error? error
function M.registration(bufnr)
	return call("workbench", "reference", bufnr)
end
---@param registration rosetta.Registration
---@param language string Registered identity, alias, or variant.
---@return boolean? success
---@return rosetta.Error? error
function M.reassign(registration, language)
	return call("workbench", "reassign", registration, language)
end
---@return rosetta.Status? status
---@return rosetta.Error? error
function M.status()
	return call("workbench", "status")
end

return M
