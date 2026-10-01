local M = {}

-- Validate Unicode scalar encodings rather than relying on permissive decoders.
function M.valid(text)
	if type(text) ~= "string" or text:find("[%z\r]") then
		return false
	end
	local i = 1
	while i <= #text do
		local a, b, c, d = text:byte(i, i + 3)
		local function continuation(n)
			return n and n >= 128 and n <= 191
		end
		if a < 128 then
			i = i + 1
		elseif a >= 194 and a <= 223 and continuation(b) then
			i = i + 2
		elseif
			a >= 224
			and a <= 239
			and continuation(b)
			and continuation(c)
			and not (a == 224 and b < 160)
			and not (a == 237 and b >= 160)
		then
			i = i + 3
		elseif
			a >= 240
			and a <= 244
			and continuation(b)
			and continuation(c)
			and continuation(d)
			and not (a == 240 and b < 144)
			and not (a == 244 and b >= 144)
		then
			i = i + 4
		else
			return false
		end
	end
	return true
end

function M.encode(lines)
	-- Neovim represents an embedded NUL as a newline inside a buffer line.
	for _, line in ipairs(lines) do
		if line:find("\n", 1, true) or not M.valid(line) then
			return nil
		end
	end
	return table.concat(lines, "\n")
end

function M.decode(text)
	if not M.valid(text) or not text:find("%S") then
		return nil
	end
	return vim.split(text, "\n", { plain = true, trimempty = false })
end

return M
