return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.8",
		dependencies = { "nvim-lua/plenary.nvim" },

		config = function()
			local builtin = require("telescope.builtin")
			vim.keymap.set("n", "<C-p>", builtin.find_files, {})
			vim.keymap.set("n", "<C-f>", builtin.live_grep, {})

			-- Define your settings with commands
			local settings = {
				{ name = "Restart LSP", command = "LspRestart" },
				{ name = "Toggle Line Blame", command = "Gitsigns toggle_current_line_blame" },
			}

			local function show_settings()
				require("telescope.pickers")
					.new({}, {
						prompt_title = "Settings",
						finder = require("telescope.finders").new_table({
							results = vim.tbl_map(function(item)
								return item.name
							end, settings),
						}),
						sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
						previewer = false, -- Disable previewer for a clean look
						attach_mappings = function(prompt_bufnr, map)
							local function run_command(index)
								local selected_item = settings[index]
								if selected_item then
									vim.api.nvim_command(selected_item.command)
								end
							end

							map("i", "<CR>", function()
								local selected_idx = require("telescope.actions.state").get_selected_entry()
								run_command(selected_idx.index)
							end)

							return true
						end,
					})
					:find()
			end

			vim.keymap.set("n", "<leader>ss", show_settings, {})
		end,
	},
}
