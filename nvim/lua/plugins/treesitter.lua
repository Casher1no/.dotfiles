return {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	opts = {
		ensure_installed = {
			"go",
			"lua",
			"regex",
			"bash",
			"markdown",
			"markdown_inline",
			"sql",
		},
		highlight = {
			enable = true,
			additional_vim_regex_highlighting = false, -- Use only Treesitter for highlighting
		},
		indent = {
			enable = true, -- Enable Treesitter-based indentation
		},
	},
}
