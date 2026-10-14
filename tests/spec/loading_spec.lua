---@diagnostic disable: duplicate-set-field
test("entry point and public require stay lazy", function()
	vim.cmd("runtime plugin/rosetta.lua")
	assert(not package.loaded["rosetta"])
	for name in pairs(package.loaded) do
		if name:match("^rosetta%.") then
			eq("rosetta.actions", name)
		end
	end
	require("rosetta")
	assert(not package.loaded["rosetta.workbench"])
	assert(vim.fn.exists(":Rosetta") == 2)
	assert(vim.fn.maparg("<Plug>(RosettaRun)", "n") ~= "")
end)

test("configure, completion and health do not activate services", function()
	vim.system = function()
		error("unexpected process")
	end
	vim.lsp.start = function()
		error("unexpected LSP startup")
	end
	assert(require("rosetta").configure({}))
	eq({ "start", "stop" }, require("rosetta.commands").complete("st", "Rosetta st", 10))
	for _, name in ipairs({ "start", "ok", "warn", "error", "info" }) do
		vim.health[name] = function() end
	end
	require("rosetta.health").check()
	assert(not package.loaded["rosetta.workbench"])
end)
