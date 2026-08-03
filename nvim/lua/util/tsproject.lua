-- tsserver puts files into an "inferred project" when the workspace has no
-- tsconfig.json/jsconfig.json, and inferred projects only contain files that
-- are open in the editor — so references/rename silently miss every closed
-- file. For projects we can't add a jsconfig to (e.g. third-party code under
-- review), preload all JS/TS/Vue sources into hidden unlisted buffers once
-- vtsls attaches; each didOpen pulls the file into the inferred project and
-- cross-file navigation behaves as if a config existed.
local M = {}

local SOURCE_EXT = { js = true, mjs = true, cjs = true, jsx = true, ts = true, tsx = true, vue = true }
local SKIP_DIRS = { node_modules = true, dist = true, build = true, coverage = true, vendor = true }
local MAX_FILES = 300
local CHUNK = 20 -- buffers loaded per event-loop tick, keeps the UI responsive

local done_roots = {}

-- Recursively gather source files under dir; exposed for headless tests.
function M._collect(dir, acc)
    acc = acc or {}
    for name, type in vim.fs.dir(dir) do
        if #acc >= MAX_FILES then
            return acc
        end
        if type == "directory" then
            if not SKIP_DIRS[name] and name:sub(1, 1) ~= "." then
                M._collect(dir .. "/" .. name, acc)
            end
        elseif type == "file" and SOURCE_EXT[name:match("%.(%w+)$") or ""] then
            table.insert(acc, dir .. "/" .. name)
        end
    end
    return acc
end

local function load_chunked(files, i, root)
    -- shortmess+=A: existing swapfiles (file open in another nvim, stale
    -- crash leftovers) would otherwise pop the blocking ATTENTION prompt
    -- for every preloaded buffer. These buffers are never edited here, so
    -- skipping the warning is safe.
    local shm = vim.o.shortmess
    vim.opt.shortmess:append("A")
    local stop = math.min(i + CHUNK - 1, #files)
    for n = i, stop do
        -- bufadd creates an unlisted buffer; bufload reads it and runs
        -- filetype detection, which is what makes vtsls attach and didOpen.
        pcall(function()
            vim.fn.bufload(vim.fn.bufadd(files[n]))
        end)
    end
    vim.o.shortmess = shm
    if stop < #files then
        vim.defer_fn(function()
            load_chunked(files, stop + 1, root)
        end, 10)
    else
        vim.notify(
            ("vtsls: no ts/jsconfig in %s — preloaded %d files so references cover the whole project")
                :format(vim.fn.fnamemodify(root, ":~"), #files),
            vim.log.levels.INFO
        )
    end
end

-- Called from the LspAttach autocmd (plugins/lsp.lua) for vtsls clients.
function M.preload(client, bufnr)
    local root = client.root_dir
    if not root or done_roots[root] then
        return
    end
    done_roots[root] = true

    local file = vim.api.nvim_buf_get_name(bufnr)
    local configs = vim.fs.find({ "tsconfig.json", "jsconfig.json" }, {
        upward = true,
        path = vim.fs.dirname(file),
        stop = vim.fs.dirname(root),
    })
    if #configs > 0 then
        return -- real project config exists; tsserver handles discovery itself
    end

    local files = M._collect(root)
    if #files == 0 then
        return
    end
    if #files >= MAX_FILES then
        vim.notify(
            ("vtsls preload hit the %d-file cap; some files may stay outside the project"):format(MAX_FILES),
            vim.log.levels.WARN
        )
    end
    vim.schedule(function()
        load_chunked(files, 1, root)
    end)
end

return M
