local M = {}
local commands = require("rosetta.actions")

function M.execute(args)
	local name = args[1] or "start"
	if not vim.list_contains(commands, name) or (name ~= "start" and #args > 1) then
		require("rosetta.util").notify(
			"Invalid arguments; use :Rosetta {start|run|stop|layout|reconnect|variant|model}"
		)
		return
	end
	local api = require("rosetta")
	local result, err
	if name == "start" then
		local inputs = #args > 1 and vim.list_slice(args, 2) or nil
		result, err = api.start(inputs)
	else
		result, err = api[name]()
	end
	if not result and err then
		require("rosetta.util").notify(err.message)
	end
end

function M.complete(lead, line, position)
	local prefix = line:sub(1, position)
	local tokens = vim.split(prefix, "%s+", { trimempty = true })
	-- Command completion receives Ex modifiers as part of CmdLine. Discard the
	-- prefix through the actual command, retaining only Rosetta's arguments.
	local command_index
	for i, token in ipairs(tokens) do
		if token:gsub("^:", "") == "Rosetta" then
			command_index = i
			break
		end
	end
	if not command_index then
		return {}
	end
	tokens = vim.list_slice(tokens, command_index)
	local finishing = prefix:match("%s$") ~= nil
	local candidates = {}
	if #tokens <= 1 or (#tokens == 2 and not finishing) then
		candidates = commands
	elseif tokens[2] == "start" then
		candidates = vim.tbl_keys(require("rosetta.config").get().resolver.inputs)
	end
	local result = {}
	for _, item in ipairs(candidates) do
		if item:sub(1, #lead):lower() == lead:lower() then
			result[#result + 1] = item
		end
	end
	table.sort(result)
	return result
end

return M
