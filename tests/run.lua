-- Run each spec in a fresh editor so module state and autocmds cannot leak.
local root = vim.fn.getcwd()
local failed = false
for _, spec in ipairs(vim.fn.glob("tests/spec/*_spec.lua", false, true)) do
	local result = vim.system({
		vim.v.progpath,
		"--headless",
		"-u",
		"NONE",
		"-i",
		"NONE",
		"--noplugin",
		"-n",
		"-l",
		root .. "/tests/runner.lua",
		spec,
	}, { text = true }):wait(30000)
	io.stdout:write(result.stdout or "")
	io.stdout:write(result.stderr or "")
	io.stdout:write("\n")
	if result.code ~= 0 then
		failed = true
	end
end
vim.cmd(failed and "cquit 1" or "quit")
