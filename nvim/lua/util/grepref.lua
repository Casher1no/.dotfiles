-- Grep fallback for LSP references (merged in by util/references.lua).
-- Intelephense cannot type dynamic Eloquent results — `Link::where(...)
-- ->first()` goes through __callStatic and comes back as mixed — so method
-- calls on such values never appear in textDocument/references. Ripgrep the
-- project for `->word(` / `::word(` call sites instead and let the picker
-- merge them in. Text-based, so a same-named method on an unrelated class
-- also matches; hits are marked ·grep in the picker for that reason.
local M = {}

-- Find method-call sites of `word` under `root`; cb(items) on the main
-- loop with quickfix-style items ({ filename, lnum, col, text }).
function M.method_calls(word, root, cb)
    if vim.fn.executable("rg") ~= 1 or not word or word == "" then
        cb({})
        return
    end
    -- vendor/ and node_modules/ are excluded explicitly: rg only honors
    -- .gitignore inside a git repository, and not every project is one.
    vim.system({
        "rg",
        "--vimgrep",
        "--no-heading",
        "-g",
        "*.php",
        "-g",
        "!vendor/**",
        "-g",
        "!node_modules/**",
        [[(->|::)\s*]] .. word .. [[\s*\(]],
        root,
    }, { text = true }, function(out)
        local items = {}
        for line in (out.stdout or ""):gmatch("[^\n]+") do
            local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
            if file then
                items[#items + 1] = {
                    filename = file,
                    lnum = tonumber(lnum),
                    col = tonumber(col),
                    text = text,
                    via_grep = true,
                }
            end
        end
        vim.schedule(function()
            cb(items)
        end)
    end)
end

return M
