local M = {}

function M.check()
	vim.health.start("rosetta.nvim")
	if vim.fn.has("nvim-0.12.5") == 1 then
		vim.health.ok("Neovim meets the tested API floor (0.12.5)")
	else
		vim.health.error("Neovim 0.12.5 or newer is required")
	end
	local config = require("rosetta.config").get()
	if vim.fn.executable(config.http.executable) == 1 then
		vim.health.ok("curl executable is available (tested with 8.7.1)")
	else
		vim.health.error("Install curl for provider operations")
	end
	for _, dependency in ipairs({ "telescope", "plenary" }) do
		if #vim.api.nvim_get_runtime_file("lua/" .. dependency .. "/", false) > 0 then
			vim.health.ok(dependency .. " is on the runtime path")
		else
			vim.health.warn("Load " .. dependency .. " to use the model/variant pickers")
		end
	end
	if not config.provider.base_url or not config.provider.model then
		vim.health.warn("Configure an explicit provider endpoint and initial model (or select a discovered model)")
	end
	if config.provider.model and not config.provider.profiles[config.provider.model] then
		vim.health.warn("A usable model budget profile is required; probes do not establish document budgets")
	end
	vim.health.info(
		"Credential source: "
			.. (config.credentials.command and "configured command" or "environment")
			.. "; no credentials were read"
	)
	if config.checker.enabled then
		if vim.fn.executable(config.checker.cmd[1]) == 1 then
			vim.health.ok(
				"Configured checker executable is available; locale/profile compatibility is user-provisioned"
			)
		else
			vim.health.warn("Optional checker executable is unavailable")
		end
	else
		vim.health.info("Optional LTeX+ checking is disabled")
	end
	for _, slot in ipairs(require("rosetta.registry").resolve_list(config.resolver, config.languages)) do
		local variant = slot.definition.variants[slot.variant]
		if require("rosetta.spell").available(variant.spell) then
			vim.health.ok(slot.id .. ": native dictionary/region available")
		else
			vim.health.info(slot.id .. ": no native dictionary/region available; no download attempted")
		end
	end
	local _, reason = require("rosetta.completion").supported()
	vim.health.info(reason)
	vim.health.info("Completed translations wait for Normal mode before replacement. See :help rosetta-undo")
	vim.health.info("No network requests, credential commands, checker startup, or probes were performed")
end

return M
