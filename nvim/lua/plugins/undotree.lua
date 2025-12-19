return {
	"mbbill/undotree",
	config = function()
		vim.g.undotree_DiffCommand = "FC"
	end,
	keys = {
		{
			"<leader>ut",
			function()
				vim.cmd.UndotreeToggle()
			end,
			desc = "Toggle Undotree",
		},
	},
}
