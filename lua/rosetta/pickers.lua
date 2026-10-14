local u = require("rosetta.util")
local M = {}

function M.open(title, entries, label, select)
	local ok, pickers = pcall(require, "telescope.pickers")
	u.check(ok, "dependency", "Install/load Telescope and Plenary to use Rosetta pickers")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	pickers
		.new({}, {
			prompt_title = title,
			finder = require("telescope.finders").new_table({
				results = entries,
				entry_maker = function(entry)
					return { value = entry, display = label(entry), ordinal = label(entry) }
				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt)
				actions.select_default:replace(function()
					local selected = action_state.get_selected_entry()
					actions.close(prompt)
					if not selected then
						return
					end
					local _, err = u.try(select, selected.value)
					if err then
						u.notify(err.message)
					end
				end)
				return true
			end,
		})
		:find()
	return { accepted = true }
end

return M
