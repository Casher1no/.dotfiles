return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"MunifTanjim/nui.nvim",
	},

	keys = {
		{
			"<leader>e",
			"<cmd>Neotree toggle<cr>",
			desc = "Toggle Neo-tree",
		},
	},

	opts = {
		window = {
			position = "right",
			-- width = 40,
		},

		default_component_configs = {
			indent = {
				indent_size = 2,
				padding = 1,
				with_markers = false,
				highlight = "NeoTreeIndentMarker",
				with_expanders = true,
				expander_collapsed = "",
				expander_expanded = "",
				expander_highlight = "NeoTreeExpander",
			},
		},

		filesystem = {
			bind_to_cwd = false,
			follow_current_file = { enabled = true },
			use_libuv_file_watcher = true,

			filtered_items = {
				visible = false,
				hide_dotfiles = false,
				hide_gitignore = true,

				hide_by_pattern = {
					"*.meta",
					"*.cs.uid",
				},

				never_show = {
					".git",
				},
			},
		},
	},
}
