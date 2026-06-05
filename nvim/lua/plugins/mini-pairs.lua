return {
    "echasnovski/mini.pairs",
    version = false,
    event = "InsertEnter",
    opts = {
        -- Auto-pair these; also handles skipping over the close char and
        -- deleting both halves with <BS>.
        modes = { insert = true, command = false, terminal = false },
    },
}
