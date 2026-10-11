local M = {}

-- Spell format v50, region section 0. Inspect metadata before enabling spell.
local function regions(path)
	local fd = vim.uv.fs_open(path, "r", 0)
	if not fd then
		return nil
	end
	local magic = vim.uv.fs_read(fd, 9, 0)
	if magic ~= "VIMspell\50" then
		vim.uv.fs_close(fd)
		return nil
	end
	local offset = 9
	---@type string?
	local result = ""
	for _ = 1, 256 do
		local section = vim.uv.fs_read(fd, 6, offset)
		if not section or #section < 1 then
			break
		end
		local id = section:byte(1)
		if id == 255 then
			break
		end
		if #section ~= 6 then
			result = nil
			break
		end
		local a, b, c, d = section:byte(3, 6)
		local length = ((a * 256 + b) * 256 + c) * 256 + d
		if id == 0 then
			if length <= 16 then
				result = vim.uv.fs_read(fd, length, offset + 6)
			else
				result = nil
			end
			break
		end
		offset = offset + 6 + length
	end
	vim.uv.fs_close(fd)
	return result
end

function M.available(mapping)
	if not mapping then
		return false
	end
	local base, region = mapping:match("^([^_]+)_?(.*)$")
	for _, encoding in ipairs({ vim.o.encoding, "ascii" }) do
		local paths = vim.api.nvim_get_runtime_file("spell/" .. base .. "." .. encoding .. ".spl", false)
		if paths[1] then
			local available = regions(paths[1])
			if available == nil then
				return false
			end
			if region == "" then
				return true
			end
			for i = 1, #available, 2 do
				if available:sub(i, i + 1) == region then
					return true
				end
			end
			return false
		end
	end
	return false
end

return M
