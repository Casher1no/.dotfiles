vim.opt.termguicolors = true

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.wrap = false
vim.opt.relativenumber = true
vim.opt.cursorline = true

vim.opt.scrolloff = 10

-- Live preview of :substitute in a split — as you type `:%s/ga/ka/g` every
-- match is highlighted and the result previewed before you hit <CR>.
vim.opt.inccommand = "split"

vim.opt.number = true
vim.opt.signcolumn = "yes:1"
-- Right-margin ruler at column 120, drawn as a thin line rather than the
-- filled cell 'colorcolumn' produces (util/ruler.lua).
require("util.ruler").setup(120)

-- `this` as a keyword, readonly fields in the field colour (util/syntax.lua).
require("util.syntax").setup()

-- What persistence.nvim stores in a session (buffers, layout, cwd, …)
vim.opt.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- Persist the undo tree to disk so <C-z>/<C-S-z> still work after reopening a
-- file — without this the history dies with the buffer. Writes into the
-- default undodir (stdpath("state")/undo), which Neovim creates on demand.
vim.opt.undofile = true
vim.opt.undolevels = 10000

-- No swap files. They exist to recover unsaved work after a crash, but the
-- auto-save in config/autocmds.lua already keeps every buffer on disk and
-- 'undofile' above persists the history — so a leftover .swp has nothing the
-- real file doesn't, and only ever shows up as the blocking ATTENTION prompt
-- ("[O]pen Read-Only, (E)dit anyway, (R)ecover...") when a crash or a second
-- nvim left one behind. Off means reopening a file just shows the newest
-- contents, the way an IDE does.
vim.opt.swapfile = false

vim.g.mapleader = " "

-- An IDE never asks whether to save on the way out, so neither does this.
-- autowriteall writes a modified buffer whenever it is about to be left
-- behind: :edit, :enew, :quit, :qall, :exit, closing a window. It does NOT
-- cover :bdelete/:bwipeout, and it stops to ask about a file that changed on
-- disk underneath you — util/autosave.lua closes both of those gaps, and does
-- the pause-point saving while you work.
vim.o.autowriteall = true

-- Backstop for what still can't be written automatically: a [No Name] buffer
-- with text in it has no filename to save to, so quitting asks "Save
-- changes?" (IDE close dialog) rather than failing with E37/E162.
vim.o.confirm = true

-- Save file with Ctrl+S
vim.keymap.set("n", "<C-S>", ":w<CR>", { desc = "Save file" })
vim.keymap.set("i", "<C-S>", "<Esc>:w<CR>", { desc = "Save file" })

vim.keymap.set("n", "<C-v>", '"+p', { desc = "Paste from clipboard" })
vim.keymap.set("v", "<C-v>", '"+P', { desc = "Paste from clipboard" })
vim.keymap.set("i", "<C-v>", "<C-r><C-o>+", { desc = "Paste from clipboard" })

-- Terminal mode needs its own paste: <C-r> doesn't exist there and the buffer
-- isn't modifiable, so `p` has nothing to paste into. Write the register
-- straight down the job's channel instead — the same thing your terminal
-- emulator does. Newlines become <CR> so a multi-line paste runs line by line
-- the way it would in any other terminal.
local function terminal_paste()
    local job = vim.b.terminal_job_id
    if not job then
        return
    end
    local text = vim.fn.getreg("+"):gsub("\r\n", "\n"):gsub("\n", "\r")
    vim.api.nvim_chan_send(job, text)
end
vim.keymap.set("t", "<C-v>", terminal_paste, { desc = "Paste from clipboard" })
vim.keymap.set("t", "<D-v>", terminal_paste, { desc = "Paste from clipboard" })

vim.keymap.set("v", "<C-x>", '"+d', { desc = "Cut to clipboard" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy to clipboard" })

-- Same clipboard shortcuts on the Mac Cmd key. These fire in GUI clients
-- (Neovide); in iTerm2 Cmd isn't forwarded to the app, so map Cmd+C/V/X to
-- "Send Hex Code" 0x03/0x16/0x18 (same trick as Cmd+6 below) which lands on
-- the Ctrl mappings above.
vim.keymap.set("v", "<D-c>", '"+y', { desc = "Copy to clipboard" })
vim.keymap.set("v", "<D-x>", '"+d', { desc = "Cut to clipboard" })
vim.keymap.set("n", "<D-v>", '"+p', { desc = "Paste from clipboard" })
vim.keymap.set("v", "<D-v>", '"+P', { desc = "Paste from clipboard" })
vim.keymap.set("i", "<D-v>", "<C-r><C-o>+", { desc = "Paste from clipboard" })
vim.keymap.set("c", "<D-v>", "<C-r>+", { desc = "Paste from clipboard" })

-- Visual-block (column) selection: the default key is Ctrl+V, which the
-- paste mapping above takes over, so Alt+V enters it instead. Extend the
-- column with j/k or the arrow keys.
vim.keymap.set({ "n", "x" }, "<A-v>", "<C-v>", { desc = "Visual block selection" })
-- macOS: when Option isn't configured as Meta, Option+V arrives as the
-- composed character "√" instead of <A-v> — map that spelling too.
vim.keymap.set({ "n", "x" }, "√", "<C-v>", { desc = "Visual block selection" })
-- Neovide composes Option by default; this makes it send <A-...> instead.
vim.g.neovide_input_macos_option_key_is_meta = "both"
-- Typing on all selected lines at once (live, multi-cursor style) is wired
-- up in plugins/multicursor.lua: stack carets with Ctrl+Alt+Up/Down, or
-- block-select with Alt+V and then press i/a.

-- Pasting over a visual selection normally yanks the replaced text into the
-- unnamed register, clobbering what you copied. Visual-mode P pastes without
-- that side effect, so repeated pastes keep pasting the same text.
vim.keymap.set("x", "p", "P", { desc = "Paste over selection without losing the yank" })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })
vim.keymap.set("v", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "<A-Up>", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

-- Same as J/K above, but with Option (Alt) on Mac. Option sends the <A-...>
-- modifier in GUI clients (Neovide) and terminals set to "Option as Meta".
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })
vim.keymap.set("v", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "<A-Up>", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

-- No selection: move just the current line.
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move current line down" })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move current line up" })
vim.keymap.set("n", "<A-Down>", ":m .+1<CR>==", { desc = "Move current line down" })
vim.keymap.set("n", "<A-Up>", ":m .-2<CR>==", { desc = "Move current line up" })

-- Shift+Up/Down: move the CURSOR 45 lines, instantly. Not a scroll — the
-- cursor lands on the new line and the view follows it, keeping 'scrolloff'
-- lines of context. These used to run neoscroll's animated ctrl_u/ctrl_d,
-- which crawled through its easing animation on Windows terminals and on macOS
-- moved the viewport without taking the cursor with it.
--
-- The count is clamped to the buffer: a bare `45j` with fewer than 45 lines
-- left beeps and moves nothing at all, which made the key feel dead near the
-- end of a file.
--
-- An open K popup (docs or error float) still wins and scrolls its own
-- contents instead, leaving the code where it is — see util/hover.lua.
local JUMP_LINES = 45

local function line_jump(dir) -- 1 = down, -1 = up
	return function()
		if require("util.hover").scroll(dir * 4) then
			return
		end
		local cur, last = vim.fn.line("."), vim.fn.line("$")
		local target = dir > 0 and math.min(cur + JUMP_LINES, last) or math.max(cur - JUMP_LINES, 1)
		local count = math.abs(target - cur)
		if count > 0 then
			-- feedkeys rather than nvim_win_set_cursor: j/k carry the desired
			-- column across short lines, and in visual mode the selection
			-- extends to the new cursor position instead of being dropped.
			vim.api.nvim_feedkeys(count .. (dir > 0 and "j" or "k"), "n", false)
		end
	end
end

-- Sideways, same idea: scroll an open popup, otherwise the default word motion.
local function popup_hscroll(dir) -- 1 = right, -1 = left
	return function()
		if require("util.hover").hscroll(dir * 8) then
			return
		end
		vim.cmd("normal! " .. (dir > 0 and "w" or "b"))
	end
end

vim.keymap.set({ "n", "v", "x" }, "<S-Up>", line_jump(-1), { desc = "Jump 45 lines up" })
vim.keymap.set({ "n", "v", "x" }, "<S-Down>", line_jump(1), { desc = "Jump 45 lines down" })
vim.keymap.set({ "n", "v", "x" }, "<S-Left>", popup_hscroll(-1), { desc = "Scroll popup left / word back" })
vim.keymap.set({ "n", "v", "x" }, "<S-Right>", popup_hscroll(1), { desc = "Scroll popup right / word forward" })

vim.keymap.set("n", "<C-z>", "u", { desc = "Undo last action" })
vim.keymap.set("i", "<C-z>", "<C-o>u", { desc = "Undo last action in insert mode" })

-- Redo, to pair with the <C-z> undo above. <C-S-z> only reaches Neovim from
-- terminals that send distinct modified keys (kitty keyboard protocol / CSI u)
-- and from GUI clients like Neovide; <C-y> is the fallback that always works,
-- and native <C-r> keeps working regardless.
vim.keymap.set("n", "<C-S-z>", "<C-r>", { desc = "Redo last undone action" })
vim.keymap.set("i", "<C-S-z>", "<C-o><C-r>", { desc = "Redo last undone action in insert mode" })
vim.keymap.set("n", "<C-y>", "<C-r>", { desc = "Redo last undone action" })
vim.keymap.set("i", "<C-y>", "<C-o><C-r>", { desc = "Redo last undone action in insert mode" })

-- Go to previous (alternate) file with Cmd+6.
-- In iTerm2 this fires because Cmd+6 is set to send 0x1e (= <C-^>); this
-- mapping also makes Cmd+6 work directly in GUI clients like Neovide.
vim.keymap.set("n", "<D-6>", "<C-^>", { desc = "Go to previous file" })

vim.keymap.set("i", "<C-h>", "<C-w>", { desc = "Delete previous word in insert mode" })

vim.api.nvim_set_keymap("n", "<C-h>", ":vertical resize -2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", ":resize +2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-k>", ":resize -2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-l>", ":vertical resize +2<CR>", { noremap = true, silent = true })

-- Focus the next / previous window (split), e.g. jump between two side-by-side files
vim.keymap.set("n", "<leader>nb", "<C-w>w", { desc = "Focus next window" })
vim.keymap.set("n", "<leader>pb", "<C-w>W", { desc = "Focus previous window" })

-- Window navigation (jump between splits, e.g. into the references/quickfix panel)
vim.keymap.set("n", "<leader>ww", "<C-w>w", { desc = "Cycle to next window" })
vim.keymap.set("n", "<leader>wh", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<leader>wj", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<leader>wk", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<leader>wl", "<C-w>l", { desc = "Go to right window" })

-- Format the current file via LSP (ruff, intelephense, ...); warns when no
-- attached server can format (see util/format.lua). On fc, not bare f, so
-- the <leader>f* telescope keys stay delay-free.
vim.keymap.set("n", "<leader>fc", function()
    require("util.format").format()
end, { desc = "Format file" })

-- Claude Code: left-side terminal + quick context references (util/ai/claude.lua)
vim.keymap.set("n", "<leader>cc", function()
    require("util.ai.claude").toggle()
end, { desc = "Toggle Claude Code" })
vim.keymap.set("n", "<leader>cf", function()
    require("util.ai.claude").add_file()
end, { desc = "Add current file to Claude Code" })
vim.keymap.set({ "x", "n" }, "<leader>cl", function()
    require("util.ai.claude").add_lines()
end, { desc = "Add line(s) to Claude Code" })

-- / and ? search ignore case by default. No smartcase: a typed capital
-- letter must not silently flip the search to case-sensitive — that's what
-- the explicit toggle below is for.
vim.opt.ignorecase = true
vim.opt.smartcase = false

-- Match-case toggle while typing a / or ? search — same key as in the
-- Telescope pickers (util/telescope_case.lua). <C-s> adds/removes \C at the
-- start of the pattern, which forces case-sensitivity regardless of
-- 'ignorecase'. The live incsearch preview updates immediately, and n/N
-- keep the chosen case because it's part of the pattern itself. A badge on
-- the right side of the search popup shows the state (util/search_case.lua).
vim.keymap.set("c", "<C-s>", function()
    require("util.search_case").toggle()
end, { desc = "Toggle match case (search)" })
require("util.search_case").setup()

-- Centered view for wide monitors: pads the gutter so the code column sits
-- in the middle of the window, without opening the empty side windows the
-- usual plugins for this use (util/centered.lua). State survives restarts.
vim.keymap.set("n", "<leader>zz", function()
    require("util.centered").toggle()
end, { desc = "Toggle centered view" })
require("util.centered").setup()

-- Esc also closes an open K popup (docs/error, see util/hover.lua) and
-- clears search highlight
vim.keymap.set("n", "<Esc>", function()
    require("util.hover").close()
    vim.cmd.nohlsearch()
end, { desc = "Escape: close docs popup, clear search highlight" })
vim.keymap.set("i", "<Esc>", "<cmd>nohlsearch<CR><Esc>", { desc = "Escape and clear search highlight" })

-- Replace-in-file: open the :substitute bar prefilled with the word under the
-- cursor (whole-word), cursor waiting in the replacement slot. Type the new
-- text and <CR> — inccommand previews every match live as you type.
vim.keymap.set("n", "<leader>sr", [[:%s/\<<C-r><C-w>\>//g<Left><Left>]], { desc = "Replace word under cursor (file)" })
-- Visual mode: replace the selected text throughout the file.
vim.keymap.set("v", "<leader>sr", [[y:%s/<C-r>0//g<Left><Left>]], { desc = "Replace selection (file)" })

-- Delete without yanking
vim.keymap.set("n", "d", '"_d', { noremap = true })
vim.keymap.set("v", "d", '"_d', { noremap = true })

-- Keep 'dd' to delete line without yanking
vim.keymap.set("n", "dd", '"_dd', { noremap = true })

-- Optional: Use leader+d for "cut" (normal delete behavior)
vim.keymap.set("n", "<leader>d", "d", { noremap = true })
vim.keymap.set("v", "<leader>d", "d", { noremap = true })

-- Centered command palette of this config's own keymaps (see lua/util/palette.lua)
vim.keymap.set("n", "<leader><space>", function()
	require("util.palette").open()
end, { desc = "Command palette" })

-- Doctor: dependency status + auto-install (util/doctor). No argument opens
-- the palette's Doctor panel; `sync` is the headless bootstrap entry point
-- (`nvim --headless "+Doctor sync"` — see bootstrap.sh at the repo root).
vim.api.nvim_create_user_command("Doctor", function(o)
	require("util.doctor").command(o.fargs)
end, {
	nargs = "*",
	-- customlist semantics: nvim doesn't filter for us
	complete = function(arg_lead)
		return vim.tbl_filter(function(s)
			return vim.startswith(s, arg_lead)
		end, { "report", "sync", "install", "update", "log" })
	end,
	desc = "Dependency doctor: report / sync / install / update / log",
})

-- Run a saved project task (manage them in the palette → Project Commands).
-- <leader>rr, not <leader>r: the latter is a strict prefix of <leader>rn
-- (LSP rename), so every press sat waiting out 'timeoutlen' first.
vim.keymap.set("n", "<leader>rr", function()
	require("util.tasks").run_interactive()
end, { desc = "Run project task" })

-- Esc in a terminal jumps straight back to the code window. <C-w>p is the
-- last-accessed window; when the terminal is the only window it's a no-op and
-- util/terminal.lua puts you back on the input line.
--
-- Cost: the terminal program no longer receives Esc — notably Claude Code,
-- where Esc cancels. Use <C-\><C-n> if you need terminal-normal mode itself.
vim.keymap.set("t", "<Esc>", [[<C-\><C-n><C-w>p]], { desc = "Back to the code window" })

-- Terminal: let <C-w> window motions work straight from terminal-insert mode
-- so you can jump out of terminals without first pressing <C-\><C-n>.
vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], { desc = "Go to left window" })
vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], { desc = "Go to lower window" })
vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], { desc = "Go to upper window" })
vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], { desc = "Go to right window" })
vim.keymap.set("t", "<C-w>w", [[<C-\><C-n><C-w>w]], { desc = "Cycle to next window" })
vim.keymap.set("t", "<C-w><Left>", [[<C-\><C-n><C-w>h]], { desc = "Go to left window" })
vim.keymap.set("t", "<C-w><Down>", [[<C-\><C-n><C-w>j]], { desc = "Go to lower window" })
vim.keymap.set("t", "<C-w><Up>", [[<C-\><C-n><C-w>k]], { desc = "Go to upper window" })
vim.keymap.set("t", "<C-w><Right>", [[<C-\><C-n><C-w>l]], { desc = "Go to right window" })
