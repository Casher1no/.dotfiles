return {
	{
		"hrsh7th/cmp-nvim-lsp",
	},
	{
		"L3MON4D3/LuaSnip",
		dependencies = {
			"saadparwaiz1/cmp_luasnip",
			"rafamadriz/friendly-snippets",
		},
	},
	{
		"hrsh7th/nvim-cmp",

		config = function()
			local cmp = require("cmp")
			require("luasnip.loaders.from_vscode").lazy_load()

			cmp.setup({
				snippet = {
					expand = function(args)
						require("luasnip").lsp_expand(args.body)
					end,
				},
				window = {
					completion = cmp.config.window.bordered(),
					documentation = cmp.config.window.bordered(),
				},
				mapping = cmp.mapping.preset.insert({
					["<C-j>"] = cmp.mapping.scroll_docs(-4, { desc = "Cmp: Scroll documentation up" }),
					["<C-k>"] = cmp.mapping.scroll_docs(4, { desc = "Cmp: Scroll documentation down" }),
					["<C-Space>"] = cmp.mapping.complete({ desc = "Cmp: Trigger completion menu" }),
					["<C-e>"] = cmp.mapping.abort({ desc = "Cmp: Abort completion" }),
					["<CR>"] = cmp.mapping.confirm({ select = true, desc = "Cmp: Confirm selection" }),
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip" }, -- For luasnip users.
				}, {
					{ name = "buffer" },
				}),
			})
		end,
	},
}
