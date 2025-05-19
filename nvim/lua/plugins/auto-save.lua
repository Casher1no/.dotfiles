return {
	"Pocco81/auto-save.nvim",
	event = { "InsertLeave", "TextChanged", "FocusLost" },
	opts = {
		enabled = true,
		execution_message = {
			message = function()
				return ""
			end,
		},
		trigger_events = { "InsertLeave", "TextChanged", "FocusLost" },
		debounce_delay = 135,
		condition = function(buf)
			local fn = vim.fn
			local utils = require("auto-save.utils.data")
			return fn.getbufvar(buf, "&modifiable") == 1 and utils.not_in(fn.getbufvar(buf, "&filetype"), {})
		end,
	},
}
