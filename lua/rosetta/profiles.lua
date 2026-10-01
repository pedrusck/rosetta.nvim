local u = require("rosetta.util")
local M = {}
local optional = { temperature = true, top_p = true, reasoning_effort = true }

function M.validate_config(provider)
	u.check(type(provider.profiles) == "table", "config", "Model profiles must be a table")
	u.keys(provider.generation, optional, "generation preferences")
	for key, value in pairs(provider.generation) do
		if key == "reasoning_effort" then
			u.check(u.string(value), "config", "Invalid reasoning effort")
		else
			u.check(
				type(value) == "number" and value == value and value >= 0 and value <= (key == "top_p" and 1 or 2),
				"config",
				"Invalid sampling preference"
			)
		end
	end
	for name, profile in pairs(provider.profiles) do
		u.check(u.string(name), "config", "Invalid model profile name")
		u.keys(profile, {
			context = true,
			completion = true,
			estimate = true,
			estimator_note = true,
			overhead = true,
			expansion = true,
			min_output = true,
			reasoning_tokens = true,
			reasoning_shares_completion = true,
			budget_field = true,
			supports = true,
			probe_tokens = true,
			chat = true,
		}, "model profile")
		for _, key in ipairs({ "context", "completion", "min_output", "probe_tokens" }) do
			u.check(
				u.integer(profile[key]),
				"config",
				"Profile context/completion/min_output/probe_tokens must be positive integers"
			)
		end
		for _, key in ipairs({ "overhead", "reasoning_tokens" }) do
			u.check(
				type(profile[key]) == "number"
					and profile[key] >= 0
					and profile[key] < math.huge
					and profile[key] == math.floor(profile[key]),
				"config",
				"Profile overhead/reasoning_tokens must be nonnegative integers"
			)
		end
		u.check(u.positive(profile.expansion), "config", "Profile expansion must be positive")
		u.check(
			type(profile.estimate) == "function" and u.string(profile.estimator_note),
			"config",
			"Profile requires an estimator and its justification"
		)
		u.check(type(profile.reasoning_shares_completion) == "boolean", "config", "Specify reasoning-token accounting")
		u.check(
			profile.budget_field == "max_tokens" or profile.budget_field == "max_completion_tokens",
			"config",
			"Unsupported output budget field"
		)
		u.keys(profile.supports or {}, optional, "supported parameters")
		for _, supported in pairs(profile.supports or {}) do
			u.check(type(supported) == "boolean", "config", "Parameter support must be boolean")
		end
		u.check(profile.chat == nil or type(profile.chat) == "boolean", "config", "chat must be boolean")
	end
end

function M.budget(provider, model, messages, source_text, probe)
	local profile = provider.profiles[model]
	u.check(profile and profile.chat ~= false, "budgets", "Configure a usable chat model budget profile")
	local function estimate(value)
		local ok, result = pcall(profile.estimate, value)
		u.check(
			ok and type(result) == "number" and result >= 0 and result < math.huge,
			"budgets",
			"Model token estimator failed"
		)
		return math.ceil(result)
	end
	local prompt = profile.overhead
	for _, message in ipairs(messages) do
		prompt = prompt + estimate(message.content)
	end
	local output = probe and profile.probe_tokens
		or math.max(profile.min_output, math.ceil(estimate(source_text) * profile.expansion))
	local completion = output + (profile.reasoning_shares_completion and profile.reasoning_tokens or 0)
	local context_reserve = output + profile.reasoning_tokens
	u.check(
		completion <= profile.completion and prompt + context_reserve <= profile.context,
		"budgets",
		"Complete prompt and reserved output exceed the model budget"
	)
	return profile, completion
end

return M
