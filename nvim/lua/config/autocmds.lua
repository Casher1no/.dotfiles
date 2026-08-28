-- Auto-reload: pull in changes made on disk by external tools (Unity's asset
-- pipeline, git, …). autoread only swaps the buffer in when it
-- has no unsaved changes — the auto-save below keeps buffers clean so this can
-- almost always reload silently instead of throwing the W12 conflict prompt.
vim.opt.autoread = true
local reload_group = vim.api.nvim_create_augroup("auto_reload", { clear = true })
local function can_checktime()
	-- Don't checktime from the cmdline window or while typing a command.
	return vim.fn.getcmdwintype() == "" and vim.fn.mode() ~= "c"
end
vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "CursorHoldI", "TermLeave" }, {
	group = reload_group,
	callback = function()
		if can_checktime() then
			vim.cmd("silent! checktime")
		end
	end,
})
-- Argument-less checktime stats every listed buffer, and BufEnter fires on
-- every split/buffer hop — with a session's worth of buffers that adds up, so
-- check only the entered buffer here and leave the full sweep to the rarer
-- events above.
vim.api.nvim_create_autocmd("BufEnter", {
	group = reload_group,
	callback = function(args)
		if can_checktime() then
			vim.cmd("silent! checktime " .. args.buf)
		end
	end,
})

-- The events above are all user-driven, and CursorHold fires only once per
-- idle period (nvim won't repeat it until a key is pressed), so a file
-- rewritten while you sit still — an AI agent editing in the background, a
-- branch switch — stays stale on screen. util/file_watch.lua polls each open
-- file directly and reloads it about a second after the write.
require("util.file_watch").setup()

-- Keep focused terminals in terminal mode, and make finished ones dismissible
-- instead of frozen — see util/terminal.lua for why both halves are needed.
require("util.terminal").setup()

-- checktime only refreshes buffers; language servers keep their own project
-- model and go stale the same way (phantom "cannot find X" errors after AI
-- tools or git rewrite files). util/lsp_refresh.lua pushes disk changes to
-- the servers and auto-heals unresolved references. :LspRefresh forces it.
require("util.lsp_refresh").setup()

-- :UnityNamespace / :UnityNamespaceRoot — the C# namespace refactor also
-- reachable from <leader>ca and F in the explorer.
require("util.cs_namespace_ui").setup()

-- Auto-save, and save-on-close: util/autosave.lua explains both halves and
-- which close paths 'autowriteall' (vim-options.lua) does not reach.
require("util.autosave").setup()

-- Remember the project (cwd) only when persistence actually saves a session
-- (i.e. real files were open). Launching/quitting from the dashboard with no
-- files open won't fire this, so the last real project sticks.
vim.api.nvim_create_autocmd("User", {
	pattern = "PersistenceSavePost",
	callback = function()
		require("util.session").save()
	end,
})

-- Track most-recently-used files for the project recent-files picker.
vim.api.nvim_create_autocmd("BufEnter", {
	callback = function(args)
		if vim.bo[args.buf].buftype ~= "" then
			return -- skip terminals, help, prompts, etc.
		end
		local name = vim.api.nvim_buf_get_name(args.buf)
		if name ~= "" and vim.fn.filereadable(name) == 1 then
			require("util.mru").touch(name)
		end
	end,
})

-- C# uses Allman style (opening brace on its own line), unlike the K&R style
-- mini.pairs' default `{}` pairing assumes. When `{` is typed at the end of a
-- statement (if/foreach/method/class/...), push it onto a new line with a
-- blank indented line and the matching `}` below, instead of pairing inline.
-- Auto-properties are the exception — see cs_is_property_declaration below.

-- Keywords that introduce a block of their own, so a `{` after one is never a
-- property accessor list. `new` covers object/collection initializers, which
-- are Allman-braced too (`var x = new Foo\n{\n    A = 1\n};`).
local cs_block_keywords = {}
for word in ([[class struct interface enum record namespace delegate else try
	finally do switch using lock fixed unsafe checked unchecked new get set
	add remove init where]]):gmatch("%S+") do
	cs_block_keywords[word] = true
end

-- Auto-properties stay on one line (`public float Foo { get; private set; }`)
-- even in Allman-braced code, so `{` after a property declaration has to pair
-- in place. What identifies one: after leading attribute groups are dropped,
-- the line is a bare `<modifiers> <type> <Name>` — no parens (that would be a
-- method or an `if`/`foreach` head), no `:` (a type's base list), no `=` (an
-- initializer or a lambda arrow), and no block keyword. Indexers end in `]`
-- and generic/nullable types (`Dictionary<string, int> Foo`, `float? Foo`)
-- pass, since the test is only that the final token is a plain identifier.
local function cs_is_property_declaration(before)
	local text = before:match("^%s*(.-)%s*$")
	while true do
		local rest = text:match("^%b[]%s*(.*)$")
		if not rest then
			break
		end
		text = rest
	end

	if text:find("[%(%)=:;{}]") then
		return false
	end

	local tokens = {}
	for token in text:gmatch("%S+") do
		if cs_block_keywords[token] then
			return false
		end
		tokens[#tokens + 1] = token
	end

	return #tokens >= 2 and tokens[#tokens]:match("^[%w_]+$") ~= nil
end

local function cs_allman_open_brace()
	local function default_open()
		-- Balance-aware `{` from util/pairs.lua, the same one the global
		-- insert mapping uses; a bare `{` if that is somehow unavailable.
		local ok, keys = pcall(function()
			return require("util.pairs").open("{")
		end)
		vim.api.nvim_feedkeys(ok and keys or "{", "n", true)
	end

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local before = line:sub(1, col)
	local after = line:sub(col + 1)

	-- Only expand when `{` closes off a fresh statement: something before
	-- it, nothing but trailing whitespace after (not a mid-line initializer
	-- like `new() { ... }` or an interpolated string `$"{expr}"`).
	if before:match("^%s*$") or after:match("%S") then
		default_open()
		return
	end

	local ts_ok, node = pcall(vim.treesitter.get_node, { pos = { row - 1, math.max(col - 1, 0) } })
	if ts_ok and node then
		local node_type = node:type()
		if node_type:find("comment") or node_type:find("string") then
			default_open()
			return
		end
	end

	if cs_is_property_declaration(before) then
		default_open()
		return
	end

	local indent = line:match("^%s*")
	local shiftwidth = vim.bo.shiftwidth > 0 and vim.bo.shiftwidth or vim.bo.tabstop
	local inner_indent = vim.bo.expandtab and (indent .. string.rep(" ", shiftwidth)) or (indent .. "\t")

	vim.api.nvim_buf_set_lines(0, row - 1, row, false, {
		before,
		indent .. "{",
		inner_indent,
		indent .. "}",
	})
	vim.api.nvim_win_set_cursor(0, { row + 2, #inner_indent })
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "cs",
	group = vim.api.nvim_create_augroup("cs_allman_braces", { clear = true }),
	callback = function(args)
		vim.keymap.set("i", "{", cs_allman_open_brace, {
			buffer = args.buf,
			desc = "Open brace on a new line, Allman-style (C#)",
		})
	end,
})

-- C/C++: compile the current file and run it in a terminal (util/cpp.lua).
-- Buffer-local so <F8> stays free everywhere else; :CppRun is the same thing
-- for when the file is open in a split you're not focused on.
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "cpp", "c" },
	group = vim.api.nvim_create_augroup("cpp_build_run", { clear = true }),
	callback = function(args)
		local function run()
			require("util.cpp").run()
		end
		vim.keymap.set("n", "<F8>", run, { buffer = args.buf, desc = "C++: build and run this file" })
		vim.keymap.set("n", "<leader>cr", run, { buffer = args.buf, desc = "C++: build and run this file" })
	end,
})

vim.api.nvim_create_user_command("CppRun", function()
	require("util.cpp").run()
end, { desc = "Compile the current C/C++ file and run it" })

-- Modifier keywords in keyword-purple, IDE-style. jdtls (and other servers)
-- report `private`, `static`, `final`, `public` — and in Java even `class` —
-- as the semantic token `modifier`, which nvim links to @type.qualifier, i.e.
-- the type color (yellow in one dark). Semantic tokens outrank treesitter, so
-- those words came out yellow even though treesitter already captured them as
-- @keyword.modifier. Point the token back at that capture. The `.java`-style
-- per-filetype variants inherit it through the @-group fallback, and the
-- ColorScheme hook re-applies it because a theme swap clears the link.
local semantic_group = vim.api.nvim_create_augroup("semantic_token_colors", { clear = true })
local function link_semantic_tokens()
	vim.api.nvim_set_hl(0, "@lsp.type.modifier", { link = "@keyword.modifier" })
end
link_semantic_tokens()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = semantic_group,
	callback = link_semantic_tokens,
})
