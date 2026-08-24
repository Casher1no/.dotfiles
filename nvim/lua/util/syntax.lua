-- IDE-style corrections to the syntax colours the themes ship.
--
-- 1. `this` is a keyword in the C-family languages, not a variable. Several
--    themes (onedark among them) paint @variable.builtin the same yellow they
--    use for types, so `this._visible` read as one long yellow blob; linked to
--    @keyword it gets the colour of `public` / `return` instead.
--
-- 2. A readonly field keeps the field colour. Neovim paints an LSP semantic
--    token with three groups at rising priority: the type
--    (@lsp.type.property, 125), the modifier (@lsp.mod.readonly, 126) and the
--    pair (@lsp.typemod.property.readonly, 127). Themes colour the modifier
--    group like a constant and leave the pair undefined, so every
--    `private readonly _x` came out constant-yellow rather than field-red.
--    Defining the pair, which outranks both, puts the field colour back.
--
-- 3. A parameter looks like a parameter. Themes that paint @variable.parameter
--    the same colour as any other variable (onedark does) get the theme's
--    number colour instead — its warm accent, the orange in onedark — and the
--    LSP parameter token is pointed at the same group, so a parameter reads
--    the same at its declaration and at every later use. Without that second
--    half only declarations were marked: treesitter can see `value` is a
--    parameter in the signature, but inside the body it is just an
--    identifier, and every theme leaves @lsp.type.parameter uncoloured.
--
-- All three are written as links to groups the active theme defines, so they follow
-- whichever colourscheme from plugins/themes.lua is picked. Highlight names
-- ending in a language ("@variable.builtin.typescript") are what the
-- treesitter highlighter actually paints with, and themes define those
-- directly — so the language has to be spelled out; the @lsp groups fall back
-- from "@lsp.typemod.property.readonly.<lang>" to the plain name on their own.
local M = {}

-- Languages where `this` (or `$this`) is a keyword. Names are treesitter
-- parser names, which is what the highlight group is suffixed with.
local this_is_a_keyword = {
    "typescript",
    "tsx",
    "javascript",
    "jsx",
    "java",
    "c_sharp",
    "php",
    "cpp",
    "dart",
    "kotlin",
    "scala",
    "swift",
}

local function fg(group)
    return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
end

local function apply()
    for _, lang in ipairs(this_is_a_keyword) do
        vim.api.nvim_set_hl(0, "@variable.builtin." .. lang, { link = "@keyword" })
    end
    vim.api.nvim_set_hl(0, "@lsp.typemod.property.readonly", { link = "@lsp.type.property" })
    if fg("@variable.parameter") == fg("@variable") then
        vim.api.nvim_set_hl(0, "@variable.parameter", { link = "@number" })
    end
    -- After the line above, so themes that already had their own parameter
    -- colour keep it at the use sites too.
    vim.api.nvim_set_hl(0, "@lsp.type.parameter", { link = "@variable.parameter" })
end

function M.setup()
    apply()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("syntax_tweaks", { clear = true }),
        callback = apply,
    })
end

return M
