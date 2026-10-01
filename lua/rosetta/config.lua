local u = require("rosetta.util")
local M = {}
local defaults = {
	languages = { "ca", "de", "en" },
	variants = {},
	registry = {},
	provider = {
		base_url = false,
		model = false,
		allow_http = false,
		profiles = {},
		generation = { temperature = 0.2 },
	},
	credentials = { env = "ROSETTA_API_KEY", command = false, timeout_ms = 10000, max_bytes = 16384 },
	http = {
		executable = "curl",
		timeout_ms = 30000,
		body_bytes = 8388608,
		header_bytes = 65536,
		stderr_bytes = 16384,
	},
	checker = {
		enabled = false,
		cmd = { "ltex-ls-plus" },
		settings = {},
		debounce_ms = 300,
		locales = {},
		hosted = false,
	},
	corrections = {
		max_suggestions = 20,
		timeout_ms = 25,
		action_timeout_ms = 500,
		max_line_bytes = 4096,
		max_word_bytes = 128,
		max_actions = 64,
		max_bytes = 16384,
	},
	layout = { min_columns = 45 },
}
local current

function M.url(value, allow_http)
	u.check(u.string(value), "endpoint", "Configure an explicit provider base_url")
	local scheme, authority, path = value:match("^(https?)://([^/]+)(.*)$")
	u.check(
		scheme and not authority:find("[@?#%s]") and not path:find("[?#%s]") and not value:find("\\"),
		"endpoint",
		"Use a base URL without credentials, query, fragment, or whitespace"
	)
	u.check(scheme == "https" or allow_http, "endpoint", "HTTP requires provider.allow_http=true")
	return scheme .. "://" .. authority:lower() .. path:gsub("/+$", "")
end

local function command(value)
	u.check(u.list(value) and #value > 0, "config", "Commands must be nonempty argument arrays")
	for _, arg in ipairs(value) do
		u.check(type(arg) == "string" and not arg:find("%z"), "config", "Invalid command argument")
	end
end

function M.candidate(opts)
	opts = opts or {}
	local allowed = {}
	for key in pairs(defaults) do
		allowed[key] = true
	end
	u.keys(opts, allowed, "configuration")
	for _, key in ipairs({ "provider", "credentials", "http", "checker", "corrections", "layout" }) do
		if opts[key] ~= nil then
			local keys = {}
			for name in pairs(defaults[key]) do
				keys[name] = true
			end
			if key == "provider" then
				keys.discovery = true
			end
			u.keys(opts[key], keys, key)
		end
	end
	local result = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	-- Lists and registry/profile maps are replacements, never index-wise merges.
	for _, key in ipairs({ "languages", "registry", "variants" }) do
		if opts[key] ~= nil then
			result[key] = vim.deepcopy(opts[key])
		end
	end
	for _, key in ipairs({ "timeout_ms", "body_bytes", "header_bytes", "stderr_bytes" }) do
		u.check(u.integer(result.http[key]), "config", "HTTP limits must be positive finite integers")
	end
	u.check(u.string(result.http.executable), "config", "Invalid curl executable")
	u.check(
		u.integer(result.credentials.timeout_ms) and u.integer(result.credentials.max_bytes),
		"config",
		"Credential limits must be positive finite integers"
	)
	u.check(
		u.string(result.credentials.env) and result.credentials.env:match("^[A-Za-z_][A-Za-z0-9_]*$"),
		"config",
		"Invalid credential environment variable"
	)
	if result.credentials.command then
		command(result.credentials.command)
	end
	for _, value in pairs(result.corrections) do
		u.check(u.integer(value), "config", "Correction bounds must be positive finite integers")
	end
	u.check(u.integer(result.layout.min_columns), "config", "Layout threshold must be a positive integer")
	u.check(
		type(result.checker.enabled) == "boolean" and type(result.checker.hosted) == "boolean",
		"config",
		"Checker flags must be booleans"
	)
	u.check(u.integer(result.checker.debounce_ms), "config", "Checker debounce must be a positive integer")
	command(result.checker.cmd)
	u.check(
		type(result.checker.settings) == "table" and type(result.checker.locales) == "table",
		"config",
		"Checker settings/locales must be tables"
	)
	for locale, value in pairs(result.checker.locales) do
		u.check(
			u.string(locale) and type(value) == "boolean",
			"config",
			"Checker locales map language tags to booleans"
		)
	end
	local ltex = result.checker.settings.ltex
	if ltex ~= nil then
		u.check(type(ltex) == "table", "config", "checker.settings.ltex must be a table")
		if ltex.enabled ~= nil then
			u.check(u.list(ltex.enabled), "config", "checker.settings.ltex.enabled must be a list")
			for _, filetype in ipairs(ltex.enabled) do
				u.check(u.string(filetype), "config", "checker.settings.ltex.enabled entries must be strings")
			end
		end
	end
	u.check(type(result.provider.allow_http) == "boolean", "config", "allow_http must be boolean")
	if result.provider.base_url then
		result.provider.base_url = M.url(result.provider.base_url, result.provider.allow_http)
	end
	u.check(result.provider.model == false or u.string(result.provider.model), "config", "Invalid initial model")
	u.check(
		result.provider.discovery == nil or type(result.provider.discovery) == "function",
		"config",
		"Discovery adapter must be a function"
	)
	require("rosetta.profiles").validate_config(result.provider)
	u.check(
		type(result.registry) == "table" and type(result.variants) == "table",
		"config",
		"Registry/default variants must be tables"
	)
	result.resolver = require("rosetta.registry").build(result.registry, result.variants)
	require("rosetta.registry").resolve_list(result.resolver, result.languages)
	return result
end

function M.get()
	if not current then
		current = M.candidate({})
	end
	return current
end

function M.configure(opts)
	local candidate = M.candidate(opts)
	current = candidate
	return true
end

return M
