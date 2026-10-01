local u = require("rosetta.util")
local M = {}
local forbidden = { mul = true, und = true, auto = true, cjk = true }

local function valid_code(code)
	return type(code) == "string" and code:match("^[A-Za-z][A-Za-z0-9-]*$") and not forbidden[code:lower()]
end

function M.build(additions, defaults)
	local definitions = vim.deepcopy(require("rosetta.languages").identities)
	for id, definition in pairs(additions) do
		u.check(valid_code(id) and id == id:lower(), "registry", "Registry identity must be a lowercase code")
		u.check(type(definition) == "table", "registry", "registry." .. id .. " must be a table")
		u.check(not definitions[id], "registry", "Registry additions cannot replace built-ins")
		definitions[id] = vim.deepcopy(definition)
		definitions[id].id = id
	end
	local index = {}
	local function bind(code, id, variant)
		u.check(valid_code(code), "registry", "Invalid registered language input")
		code = code:lower()
		local previous = index[code]
		u.check(
			not previous or (previous.id == id and (not previous.variant or previous.variant == variant)),
			"registry",
			"Registry inputs collide"
		)
		-- An identity equal to its sole variant remains identity-only input.
		if not previous then
			index[code] = { id = id, variant = variant }
		end
	end
	for id, def in pairs(definitions) do
		u.check(valid_code(id) and id == id:lower(), "registry", "Identity must be a lowercase registered code")
		u.check(u.string(def.name) and u.string(def.translation_name), "registry", "Language names are required")
		u.check(type(def.variants) == "table" and next(def.variants), "registry", "Variants are required")
		u.check(def.variants[def.default] ~= nil, "registry", "Unknown default variant")
		u.check(u.list(def.aliases), "registry", "Aliases must be a list")
		bind(id, id)
		for _, alias in ipairs(def.aliases) do
			bind(alias, id)
		end
		for vid, variant in pairs(def.variants) do
			u.check(
				type(variant) == "table",
				"registry",
				"registry." .. id .. ".variants." .. tostring(vid) .. " must be a table"
			)
			u.check(
				valid_code(vid) and u.string(variant.name) and u.string(variant.instruction),
				"registry",
				"Invalid variant definition"
			)
			u.check(
				variant.spell == false or (u.string(variant.spell) and variant.spell:match("^[a-z][a-z0-9_@-]*$")),
				"registry",
				"Explicit native mapping or false required"
			)
			u.check(
				variant.ltex == false or valid_code(variant.ltex),
				"registry",
				"Explicit LTeX+ mapping or false required"
			)
			u.check(
				variant.hosted_only == nil or type(variant.hosted_only) == "boolean",
				"registry",
				"hosted_only must be boolean"
			)
			variant.id = vid
			bind(vid, id, vid)
		end
	end
	for id, vid in pairs(defaults) do
		u.check(definitions[id] and definitions[id].variants[vid], "registry", "Invalid configured default variant")
		definitions[id].default = vid
	end
	return { definitions = definitions, inputs = index }
end

function M.compatible(a, b)
	local function semantic(def)
		local variants = {}
		for id, v in pairs(def.variants) do
			variants[id] = {
				instruction = v.instruction,
				spell = v.spell,
				ltex = v.ltex,
				hosted_only = v.hosted_only or false,
			}
		end
		return { id = def.id, translation_name = def.translation_name, variants = variants }
	end
	return vim.deep_equal(semantic(a), semantic(b))
end

function M.resolve(registry, input, retained, remembered)
	u.check(type(input) == "string", "language", "Language input must be a string")
	local entry = registry.inputs[input:lower()]
	u.check(entry, "language", "Unknown language or variant; use :Rosetta start completion")
	local def = registry.definitions[entry.id]
	if retained then
		u.check(
			M.compatible(retained.definition, def),
			"language",
			"Language definition changed; retire and recreate its registration explicitly"
		)
		def = retained.definition
	end
	local variant = entry.variant
		or (retained and retained.variant)
		or (remembered and def.variants[remembered[entry.id]] and remembered[entry.id])
		or def.default
	return { id = entry.id, definition = vim.deepcopy(def), variant = variant }
end

function M.resolve_list(registry, inputs, slots, remembered)
	u.check(u.list(inputs) and #inputs >= 2, "languages", "At least two distinct languages are required")
	local old, result, seen = {}, {}, {}
	for _, slot in ipairs(slots or {}) do
		old[slot.id] = slot
	end
	for _, input in ipairs(inputs) do
		local entry = type(input) == "string" and registry.inputs[input:lower()]
		local slot = M.resolve(registry, input, entry and old[entry.id], remembered)
		u.check(
			not seen[slot.id],
			"languages",
			"Languages must have distinct identities, including aliases and variants"
		)
		seen[slot.id] = true
		result[#result + 1] = slot
	end
	return result
end

return M
