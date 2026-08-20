-- Smarter open/closeopen rules on top of mini.pairs.
--
-- mini.pairs decides whether to insert a pair by looking only at the two
-- characters next to the cursor, so it happily doubles a quote that is really
-- closing one already on the line:
--
--     "Test.|      + "   ->   "Test."" (wanted: "Test.")
--     |Test"       + "   ->   ""Test"  (wanted: "Test")
--     foo)|        + (   ->   foo)()   (wanted: foo)( )
--
-- This module keeps mini.pairs' behavior (skip over a closer, <BS> deletes
-- both halves, neighborhood patterns) and only adds a balance check on the
-- current line: when a pair character is already unmatched there, the typed
-- key is completing it, not opening a new pair, so insert a single character.
local M = {}

-- mini.pairs' own defaults, kept in one place so the overrides stay in sync
-- with what they replace. `'` refuses to pair after a letter (don't, isn't).
local OPEN = {
    ["("] = { pair = "()", neigh_pattern = "^[^\\]" },
    ["["] = { pair = "[]", neigh_pattern = "^[^\\]" },
    ["{"] = { pair = "{}", neigh_pattern = "^[^\\]" },
}
local CLOSEOPEN = {
    ['"'] = { pair = '""', neigh_pattern = "^[^\\]" },
    ["'"] = { pair = "''", neigh_pattern = "^[^%a\\]" },
    ["`"] = { pair = "``", neigh_pattern = "^[^\\]" },
}

-- Occurrences of `char` in `s` that are not backslash-escaped, so `"a\"b"`
-- counts as two quotes rather than three.
local function count(s, char)
    local n, i = 0, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then
            i = i + 2
        else
            if c == char then
                n = n + 1
            end
            i = i + 1
        end
    end
    return n
end

-- Typing straight in front of a word: the text being wrapped is already
-- there, so the closer belongs at the far end of it, not under the cursor.
local function before_word(after)
    return after:match("^[%w_]") ~= nil
end

local function cursor_split()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    return line, line:sub(1, col), line:sub(col + 1)
end

-- `(`, `[`, `{` — a pair whose halves are distinguishable, so "unmatched" is
-- simply more closers than openers on the line. Typing `(` in `foo)` must not
-- add a second `)`; typing it in `foo(bar|)` still pairs, because that `)`
-- already belongs to the `(` before `bar`.
function M.open(key)
    local MiniPairs = require("mini.pairs")
    local info = OPEN[key]
    local line, _, after = cursor_split()
    local close = info.pair:sub(2, 2)

    if count(line, close) > count(line, key) then
        return key
    end

    if before_word(after) then
        return key
    end

    return MiniPairs.open(info.pair, info.neigh_pattern)
end

-- `"`, `'`, `` ` `` — both halves are the same character, so the line is
-- unbalanced exactly when the count is odd, and this keystroke is the one
-- that balances it.
function M.closeopen(key)
    local MiniPairs = require("mini.pairs")
    local info = CLOSEOPEN[key]
    local line, _, after = cursor_split()

    -- Sitting on the matching closer: mini.pairs steps over it instead of
    -- inserting anything, which is right regardless of the balance.
    if after:sub(1, 1) == key then
        return MiniPairs.closeopen(info.pair, info.neigh_pattern)
    end

    -- An unmatched quote is already open somewhere on the line.
    if count(line, key) % 2 == 1 then
        return key
    end

    if before_word(after) then
        return key
    end

    return MiniPairs.closeopen(info.pair, info.neigh_pattern)
end

function M.setup()
    -- Insert-mode mappings only. <BS>/<CR> keep working on their own: the
    -- pairs stay registered by mini.pairs' own setup, which these replace
    -- only as *input* mappings.
    local function map(key, fn, desc)
        vim.keymap.set("i", key, function()
            return fn(key)
        end, { expr = true, replace_keycodes = false, desc = desc })
    end

    for key in pairs(OPEN) do
        map(key, M.open, "Insert " .. key .. " (balance-aware pair)")
    end
    for key in pairs(CLOSEOPEN) do
        map(key, M.closeopen, "Insert " .. key .. " (balance-aware pair)")
    end
end

return M
