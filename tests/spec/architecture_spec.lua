test("internal require graph remains acyclic", function()
	local graph = {}
	for _, path in ipairs(vim.fn.glob("lua/rosetta/*.lua", false, true)) do
		local name = vim.fn.fnamemodify(path, ":t:r")
		local content = table.concat(vim.fn.readfile(path), "\n")
		graph[name] = {}
		for dependency in content:gmatch('require%("rosetta%.([^"]+)"%)') do
			graph[name][dependency] = true
		end
	end
	local visiting, visited = {}, {}
	local function visit(name)
		assert(not visiting[name], "circular dependency involving " .. name)
		if visited[name] then
			return
		end
		visiting[name] = true
		for dependency in pairs(graph[name] or {}) do
			visit(dependency)
		end
		visiting[name], visited[name] = nil, true
	end
	for name in pairs(graph) do
		visit(name)
	end
end)
