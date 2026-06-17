-- Saves a session per project directory on exit and restores it on demand
-- (used by the dashboard's "Continue" entry).
return {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
}
