local u = require("rosetta.util")
local Provider = {}

function Provider.new(deps)
	local M = {}
	local context
	local generation, last_endpoint, last_model = 0, nil, nil

	local function live(ctx)
		return deps.is_active() and context == ctx
	end

	function M.status()
		local ctx = context
		if not ctx then
			return { ready = false, label = "Not ready", generation = generation }
		end
		local ready = ctx.state == "usable" and not ctx.recovery and ctx.model_state == "validated" and ctx.budgets
		local label = ctx.recovery and "Reconnect required"
			or ctx.state == "preparing" and "Preparing"
			or ctx.state == "failed" and "Preparation failed"
			or ctx.model_state == "probing" and "Probing model"
			or ready and "Ready"
			or ctx.model_state == "failed" and "Model failed"
			or "Model/budgets unavailable"
		return {
			ready = ready or false,
			label = label,
			generation = ctx.generation,
			model = ctx.model,
			revision = ctx.model_revision,
			recovery = ctx.recovery or false,
		}
	end

	local function publish(ctx)
		if not live(ctx) then
			return
		end
		deps.on_changed()
		if ctx.state ~= "preparing" and ctx.model_state ~= "probing" and not ctx.waiting_metadata then
			local listeners = ctx.listeners
			ctx.listeners = {}
			for _, callback in ipairs(listeners) do
				u.callback(callback, M.status())
			end
		end
	end

	function M.observe(callback)
		if not callback then
			return
		end
		local ctx = context
		if ctx and (ctx.state == "preparing" or ctx.model_state == "probing" or ctx.waiting_metadata) then
			ctx.listeners[#ctx.listeners + 1] = callback
		else
			u.callback(callback, M.status())
		end
	end

	function M.stop()
		local ctx = context
		context = nil
		if not ctx then
			return
		end
		ctx.key = nil
		for handle in pairs(ctx.handles) do
			handle.cancel()
		end
		ctx.handles, ctx.catalog = {}, nil
		for _, callback in ipairs(ctx.listeners) do
			u.callback(callback, { cancelled = true, generation = ctx.generation })
		end
		ctx.listeners = {}
	end

	-- Generation-route errors affect the shared provider, not sibling validity.
	local function request(ctx, method, route, body, callback)
		local wrapped, inner, cancelled = {}, nil, false
		function wrapped.cancel()
			cancelled = true
			ctx.handles[wrapped] = nil
			if inner then
				inner.cancel()
			end
		end
		ctx.handles[wrapped] = true
		inner = deps.http(ctx, method, route, body, function(response)
			ctx.handles[wrapped] = nil
			if cancelled or not live(ctx) then
				return
			end
			if
				route == "/chat/completions"
				and (response.status == 401 or response.status == 403 or response.status == 429)
			then
				ctx.recovery = true
				if not ctx.reported_recovery then
					ctx.reported_recovery = true
					u.notify("Provider authentication/rate limit failure; use :Rosetta reconnect")
				end
				publish(ctx)
			end
			callback(response)
		end)
		return wrapped
	end

	local function probe(ctx)
		if not live(ctx) then
			return
		end
		ctx.waiting_metadata = false
		if not ctx.model then
			ctx.model_state = "unselected"
			publish(ctx)
			return
		end
		local body, err = u.try(require("rosetta.chat").request, ctx.config, ctx.model, {
			{
				role = "user",
				content = "Reply with a short sentence confirming that the model is working.",
			},
		}, "", true)
		if not body then
			if not ctx.discovery_finished then
				ctx.waiting_metadata = true
				publish(ctx)
				return
			end
			ctx.model_state, ctx.budgets = "failed", false
			u.notify("Model " .. ctx.model .. ": " .. (err and err.message or "Model budget unavailable"))
			publish(ctx)
			return
		end
		ctx.model_state, ctx.budgets = "probing", true
		local revision, model = ctx.model_revision, ctx.model
		ctx.probe = request(ctx, "POST", "/chat/completions", body, function(response)
			if ctx.model_revision ~= revision then
				return
			end
			local valid = not response.error
				and response.status
				and response.status >= 200
				and response.status < 300
				and require("rosetta.chat").response(response.body)
			ctx.model_state = valid and "validated" or "failed"
			if not valid then
				u.notify(
					"Model probe failed for "
						.. model
						.. (response.status and " (HTTP " .. response.status .. ")" or "")
				)
			end
			publish(ctx)
		end)
		publish(ctx)
	end

	local function discover(ctx)
		request(ctx, "GET", "/models", nil, function(response)
			ctx.discovery_finished = true
			local ok, data = pcall(vim.json.decode, response.body)
			local result
			if not response.error and response.status and response.status >= 200 and response.status < 300 and ok then
				if ctx.config.discovery then
					ok, result = pcall(ctx.config.discovery, data)
				else
					result = type(data) == "table" and { models = data.data } or nil
				end
			end
			local catalog, seen = {}, {}
			local valid = ok
				and type(result) == "table"
				and type(result.models) == "table"
				and vim.islist(result.models)
			if valid then
				for _, model in ipairs(result.models) do
					if type(model) ~= "table" or not u.string(model.id) or seen[model.id] then
						valid = false
						break
					end
					seen[model.id] = true
					catalog[#catalog + 1] = { id = model.id, chat = model.chat }
				end
				if result.profiles then
					local candidate = vim.deepcopy(ctx.config)
					local validated = pcall(function()
						u.check(type(result.profiles) == "table", "metadata", "Invalid metadata profile collection")
						candidate.profiles = vim.tbl_extend("keep", candidate.profiles, result.profiles)
						require("rosetta.profiles").validate_config(candidate)
					end)
					if validated then
						ctx.config = candidate
					else
						valid = false
					end
				end
			end
			if valid then
				ctx.catalog = catalog
			else
				ctx.discovery_error = true
				u.notify("Model discovery failed; a configured validated model can still translate")
			end
			if ctx.waiting_metadata then
				probe(ctx)
			else
				publish(ctx)
			end
		end)
	end

	function M.activate(opts)
		M.stop()
		generation = generation + 1
		local config = deps.config()
		local provider = vim.deepcopy(config.provider)
		if provider.base_url ~= last_endpoint then
			last_endpoint, last_model = provider.base_url, provider.model or nil
		elseif not last_model then
			last_model = provider.model or nil
		end
		local ctx = {
			config = provider,
			generation = generation,
			state = "preparing",
			model_revision = 1,
			model = last_model,
			model_state = "unselected",
			handles = {},
			listeners = {},
			credential_env = config.credentials.env,
		}
		context = ctx
		M.observe(opts and opts.on_complete)
		if not provider.base_url then
			ctx.state = "failed"
			u.notify("Configure an explicit provider base_url; editing remains available")
			publish(ctx)
			return
		end
		local handle
		handle = deps.credentials(vim.deepcopy(config.credentials), function(key, err)
			ctx.handles[handle] = nil
			if not live(ctx) then
				return
			end
			if not key then
				ctx.state = "failed"
				u.notify(err)
				publish(ctx)
				return
			end
			ctx.key, ctx.state = key, "usable"
			discover(ctx)
			probe(ctx)
		end)
		ctx.handles[handle] = true
	end

	local function select(ctx, revision, model, callback)
		u.check(live(ctx) and ctx.model_revision == revision, "stale_picker", "Model picker is stale; open it again")
		if ctx.model == model then
			M.observe(callback)
			return true
		end
		local offered
		for _, entry in ipairs(ctx.catalog or {}) do
			if entry.id == model and entry.chat ~= false then
				offered = true
			end
		end
		u.check(offered, "model", "Model is not offered as a compatible selection")
		local profile = ctx.config.profiles[model]
		u.check(not profile or profile.chat ~= false, "model", "Model profile is incompatible with chat")
		if ctx.probe then
			ctx.probe.cancel()
		end
		for _, listener in ipairs(ctx.listeners) do
			u.callback(listener, { cancelled = true, generation = ctx.generation, model = ctx.model })
		end
		ctx.listeners = {}
		ctx.model_revision, ctx.model, last_model = ctx.model_revision + 1, model, model
		ctx.model_state = "probing"
		M.observe(callback)
		probe(ctx)
		return true
	end

	-- A closure captures the context and revision without exposing credentials or
	-- mutable provider state to a picker.
	function M.model_choices()
		local ctx = context
		u.check(deps.is_active() and ctx, "inactive", "Model selection requires an active workbench")
		u.check(ctx.key and ctx.catalog, "discovery", "Model picker needs active credentials and discovery data")
		local entries, revision = {}, ctx.model_revision
		for _, entry in ipairs(ctx.catalog) do
			local profile = ctx.config.profiles[entry.id]
			if entry.chat ~= false and (not profile or profile.chat ~= false) then
				entries[#entries + 1] = entry.id
			end
		end
		table.sort(entries)
		return entries, function(model, callback)
			return select(ctx, revision, model, callback)
		end
	end

	function M.capture()
		local status = M.status()
		u.check(status.ready, "not_ready", status.label .. "; run is not queued")
		local ctx = context
		local config, model = vim.deepcopy(ctx.config), ctx.model
		return {
			model = model,
			is_current = function()
				return live(ctx)
			end,
			prepare = function(messages, source)
				return require("rosetta.chat").request(config, model, messages, source, false)
			end,
			dispatch = function(body, callback)
				return request(ctx, "POST", "/chat/completions", body, callback)
			end,
		}
	end

	return M
end

return Provider
