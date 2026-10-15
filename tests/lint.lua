-- Run LuaLS with the installed Neovim API metadata and temporary diagnostics.
local executable = vim.env.LUA_LS or "lua-language-server"
assert(vim.fn.executable(executable) == 1, "Install lua-language-server or set LUA_LS")
local log = vim.fn.tempname()
local result = vim.system({ executable, "--check", vim.fn.getcwd(), "--checklevel=Warning", "--logpath=" .. log }, {
	text = true,
	env = { VIMRUNTIME = vim.env.VIMRUNTIME },
}):wait(120000)
io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
vim.fn.delete(log, "rf")
vim.cmd(result.code == 0 and "quit" or "cquit 1")
