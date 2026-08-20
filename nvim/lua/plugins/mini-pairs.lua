return {
    "echasnovski/mini.pairs",
    version = false,
    event = "InsertEnter",
    opts = {
        -- Auto-pair these; also handles skipping over the close char and
        -- deleting both halves with <BS>.
        modes = { insert = true, command = false, terminal = false },
    },
    config = function(_, opts)
        require("mini.pairs").setup(opts)
        -- Replaces the insert-mode mappings with balance-aware ones so a
        -- quote that closes an already-open string is not doubled.
        require("util.pairs").setup()
    end,
}
