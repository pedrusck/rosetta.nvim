local M = {}

function M.leaves(tree, result)
	result = result or {}
	if tree[1] == "leaf" then
		result[#result + 1] = tree[2]
	else
		for _, child in ipairs(tree[2]) do
			M.leaves(child, result)
		end
	end
	return result
end

function M.subtree(tree, owned)
	local count, total = 0, 0
	for _ in pairs(owned) do
		total = total + 1
	end
	local all = M.leaves(tree)
	for _, win in ipairs(all) do
		if owned[win] then
			count = count + 1
		end
	end
	if count == total and #all == total then
		return tree
	end
	if tree[1] ~= "leaf" then
		for _, child in ipairs(tree[2]) do
			local found = M.subtree(child, owned)
			if found then
				return found
			end
		end
	end
end

function M.orientation(previous, retry, fits, minimum_width, threshold)
	if retry or not previous then
		return fits and "columns" or "rows"
	end
	if previous == "columns" and (not fits or minimum_width < threshold) then
		return "rows"
	end
	return previous
end

return M
