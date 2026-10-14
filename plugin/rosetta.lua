if vim.g.loaded_rosetta then
	return
end
vim.g.loaded_rosetta = true

vim.api.nvim_create_user_command("Rosetta", function(args)
	require("rosetta.commands").execute(args.fargs)
end, {
	nargs = "*",
	desc = "Translation and proofreading workbench",
	complete = function(lead, line, position)
		return require("rosetta.commands").complete(lead, line, position)
	end,
})

for _, action in ipairs(require("rosetta.actions")) do
	local title = action:sub(1, 1):upper() .. action:sub(2)
	vim.keymap.set("n", "<Plug>(Rosetta" .. title .. ")", function()
		require("rosetta.commands").execute({ action })
	end, { desc = "Rosetta " .. action })
end
