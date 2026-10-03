local u = require("rosetta.util")
local uv = vim.uv
local M = {}
local ledger = {}
local directory, serial = nil, 0
---@type uv.fs_stat.result?
local identity

function M.directory()
	if directory then
		return directory
	end
	local parent = uv.os_tmpdir()
	local path = parent and uv.fs_mkdtemp(parent .. "/rosetta-XXXXXX")
	if not path then
		u.fail("filesystem", "Could not create a private session directory")
	end
	---@cast path string
	local ok = uv.fs_chmod(path, 448) -- 0700
	if not ok then
		uv.fs_rmdir(path)
		u.fail("filesystem", "Could not make the session directory private")
	end
	local stat = uv.fs_lstat(path)
	if not stat then
		uv.fs_rmdir(path)
		u.fail("filesystem", "Could not inspect the session directory")
	end
	directory, identity = uv.fs_realpath(path) or path, stat
	return directory
end

local function safe_directory()
	local stat = directory and uv.fs_lstat(directory)
	return stat and identity and stat.type == "directory" and stat.ino == identity.ino and stat.dev == identity.dev
end

function M.reserve(owner, name)
	local root = M.directory()
	u.check(safe_directory(), "filesystem", "Session directory identity changed")
	serial = serial + 1
	local path = root .. "/" .. serial .. "." .. name
	ledger[path] = { owner = owner }
	return path
end

function M.remove(path)
	if not ledger[path] then
		return true
	end
	if not safe_directory() then
		return false
	end
	local stat, _, code = uv.fs_lstat(path)
	if not stat and code == "ENOENT" then
		ledger[path] = nil
		return true
	end
	if not stat or stat.type == "directory" then
		return false
	end
	-- unlink removes a symlink itself, never its destination.
	if uv.fs_unlink(path) then
		ledger[path] = nil
		return true
	end
	return false
end

function M.request(body)
	local path = M.reserve(false, "request.json")
	local fd = uv.fs_open(path, "wx", 384) -- 0600
	if not fd then
		M.remove(path)
		u.fail("filesystem", "Could not create a private request file")
	end
	---@cast fd integer
	local offset = 0
	while offset < #body do
		local count = uv.fs_write(fd, body:sub(offset + 1), offset)
		if not count or count == 0 then
			uv.fs_close(fd)
			M.remove(path)
			u.fail("filesystem", "Could not write a request file")
		end
		offset = offset + count
	end
	uv.fs_close(fd)
	return path
end

function M.cleanup(owner, all)
	local failures = 0
	for path, entry in pairs(ledger) do
		if all or entry.owner == owner then
			if not M.remove(path) then
				failures = failures + 1
			end
		end
	end
	M.prune()
	if failures > 0 then
		u.notify("Some owned temporary files could not be removed; cleanup will be retried")
	end
	return failures == 0
end

function M.prune()
	if directory and safe_directory() and not next(ledger) and uv.fs_rmdir(directory) then
		directory, identity = nil, nil
	end
end

return M
