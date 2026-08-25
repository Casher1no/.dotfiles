-- Relevance ranking for the file and grep pickers, IDE-style: a search is
-- almost always a search for *code*, so source files come first, templates
-- and stylesheets next, config/data (json, yaml, xml) below that, docs
-- lower still, and generated output (lock files, minified bundles, build
-- dirs, binaries) last. Nothing is hidden — a match in composer.json is
-- still there, just under the .php files.
--
-- Telescope sorts by score with lower = better, so ranking is a
-- multiplicative penalty on the match score: 1 leaves a row exactly where
-- the fuzzy/grep match put it, 3 pushes it three times further down. Using
-- a factor rather than a fixed offset keeps a strong match (an exact file
-- name) above a weak one from a "better" file type.
local M = {}

M.weights = {
    source = 1.0, -- .php, .java, .ts, .py …
    other_source = 1.3, -- code, but not in one of the project's own languages
    markup = 1.7, -- templates and styles: .html, .twig, .css
    config = 2.4, -- .json, .yaml, .xml, .toml, dotfiles
    doc = 3.0, -- .md, .txt, .rst
    asset = 4.0, -- images, fonts, media, compiled binaries
    generated = 6.0, -- lock files, .min.js, source maps, build output
}

-- Extension → class. Anything unlisted is treated as config (unknown
-- extensions are far more often data/dotfiles than code).
local function build(class, exts)
    local t = {}
    for _, ext in ipairs(exts) do
        t[ext] = class
    end
    return t
end

local EXT = vim.tbl_extend(
    "error",
    build("source", {
        "php", "java", "kt", "kts", "cs", "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "vue", "svelte", "py", "rb", "go", "rs", "c", "h", "cc", "cpp", "cxx",
        "hpp", "hh", "m", "mm", "swift", "scala", "dart", "lua", "sh", "bash",
        "zsh", "fish", "ps1", "sql", "pl", "pm", "ex", "exs", "erl", "clj",
        "cljs", "groovy", "r", "jl", "zig", "nim", "hs", "fs", "fsx", "vb",
        "asm", "s", "tf", "proto", "graphql", "gql",
    }),
    build("markup", {
        "html", "htm", "xhtml", "twig", "blade", "erb", "ejs", "hbs", "handlebars",
        "mustache", "jinja", "jinja2", "j2", "css", "scss", "sass", "less",
        "styl", "xaml", "razor", "cshtml",
    }),
    build("config", {
        "json", "jsonc", "json5", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "env", "properties", "xml", "plist", "csv", "tsv", "gradle", "cmake",
        "dockerfile", "editorconfig", "sln", "csproj", "props", "targets",
        "meta", "resx",
    }),
    build("doc", {
        "md", "mdx", "markdown", "txt", "rst", "adoc", "asciidoc", "org", "pdf",
        "log",
    }),
    build("asset", {
        "png", "jpg", "jpeg", "gif", "svg", "ico", "webp", "bmp", "tiff",
        "woff", "woff2", "ttf", "otf", "eot", "mp3", "mp4", "wav", "ogg",
        "webm", "zip", "gz", "tar", "rar", "7z", "exe", "dll", "so", "dylib",
        "pdb", "class", "jar", "pyc", "o", "a", "bin", "dat", "db", "sqlite",
    })
)

-- Whole file names that are data/docs regardless of extension.
local NAMES = {
    ["dockerfile"] = "config",
    ["makefile"] = "config",
    ["rakefile"] = "config",
    ["gemfile"] = "config",
    ["procfile"] = "config",
    ["license"] = "doc",
    ["changelog"] = "doc",
    ["readme"] = "doc",
    ["authors"] = "doc",
    ["contributing"] = "doc",
}

-- Machine-written files: never what a search is after, but they are huge and
-- match everything, so they sink to the bottom of the list.
local GENERATED_NAMES = {
    "%-lock%.json$",
    "%.lock$",
    "%.sum$",
    "%.min%.%w+$",
    "%.map$",
    "%.snap$",
    "%.g%.%w+$", -- generated.g.dart, api.g.cs
    "%.designer%.cs$",
    "%.generated%.%w+$",
}

-- Build output / dependency dirs. Ignored by .gitignore in most projects,
-- so this only matters for the ones without git.
local GENERATED_DIRS = {
    dist = true,
    build = true,
    out = true,
    bin = true,
    obj = true,
    target = true,
    coverage = true,
    [".next"] = true,
    [".nuxt"] = true,
    ["node_modules"] = true,
    vendor = true,
    generated = true,
    Library = true, -- Unity's import cache
    Temp = true,
}

-- The languages this project is actually written in, from the build files at
-- its root: a .java hit outranks a .lua one in a Maven project and the other
-- way round in a plugin repo. Empty when nothing is recognized, which just
-- means every source file ranks equally.
local marker_langs = {
    ["composer.json"] = { "php" },
    ["artisan"] = { "php" },
    ["pom.xml"] = { "java", "kt" },
    ["build.gradle"] = { "java", "kt", "kts" },
    ["build.gradle.kts"] = { "kt", "kts", "java" },
    ["package.json"] = { "ts", "tsx", "js", "jsx", "mjs", "cjs", "vue", "svelte" },
    ["tsconfig.json"] = { "ts", "tsx" },
    ["go.mod"] = { "go" },
    ["Cargo.toml"] = { "rs" },
    ["pyproject.toml"] = { "py" },
    ["setup.py"] = { "py" },
    ["requirements.txt"] = { "py" },
    ["Gemfile"] = { "rb" },
    ["pubspec.yaml"] = { "dart" },
    ["mix.exs"] = { "ex", "exs" },
}

local cache = { cwd = nil, langs = {} }

-- .NET has no fixed marker file name, only the *.sln / *.csproj pattern — and
-- a Unity project has neither at a predictable place. Everything here stays
-- inside the root directory: this runs behind M.penalty, i.e. once per entry
-- per keystroke, so it must never walk the tree. A recursive glob for
-- **/*.csproj used to live here and froze the picker for ~20s on the first
-- open of a Unity project (Library/ alone is ~44k files, and vim.fn.glob is
-- synchronous on the main loop with no ignore rules).
local function is_dotnet(cwd)
    -- .slnx is the current VS solution format; plain .sln is still the common
    -- one. Both are a single non-recursive readdir.
    for _, pat in ipairs({ "/*.sln", "/*.slnx", "/*.csproj", "/*.fsproj" }) do
        if vim.fn.glob(cwd .. pat, true, true)[1] then
            return true
        end
    end
    -- Unity generates its .csproj files on demand, so a freshly cloned project
    -- can have none at all. Two stats settle it (util/unity.lua).
    return require("util.unity").is_unity_project(cwd)
end

-- Extensions belonging to the project's own languages, cached per cwd.
function M.project_langs(cwd)
    cwd = cwd or vim.loop.cwd() or ""
    if cache.cwd == cwd then
        return cache.langs
    end
    local langs = {}
    for marker, exts in pairs(marker_langs) do
        if vim.loop.fs_stat(cwd .. "/" .. marker) then
            for _, ext in ipairs(exts) do
                langs[ext] = true
            end
        end
    end
    if is_dotnet(cwd) then
        langs.cs = true
    end
    cache.cwd, cache.langs = cwd, langs
    return langs
end

-- Fill the cache ahead of the first scoring pass. The pickers call this from
-- their opts/launch path so M.penalty only ever reads an already-warm table —
-- detection is cheap now, but it still has no business running inside the
-- per-entry sorter loop.
function M.prime(cwd)
    M.project_langs(cwd or vim.loop.cwd() or "")
end

-- Class of a path: "source" / "markup" / "config" / "doc" / "asset" /
-- "generated". Exposed for headless tests.
local function classify_path(path)
    local name = path:match("[^/\\]+$") or path
    local lower = name:lower()
    for _, pattern in ipairs(GENERATED_NAMES) do
        if lower:match(pattern) then
            return "generated"
        end
    end
    for segment in path:gmatch("[^/\\]+") do
        if GENERATED_DIRS[segment] then
            return "generated"
        end
    end
    if NAMES[lower] then
        return NAMES[lower]
    end
    -- Type declarations rank with the data files: the .ts they describe is
    -- almost always the hit that was wanted.
    if lower:match("%.d%.ts$") then
        return "config"
    end
    -- Double extensions carry the real type on the inside (index.blade.php is
    -- a template, not php), so try the last two before the last one.
    local double = lower:match("%.([%w]+%.[%w]+)$")
    if double and EXT[double:match("^([%w]+)")] == "markup" then
        return "markup"
    end
    local ext = lower:match("%.([%w]+)$")
    if not ext then
        -- Dotfiles (.gitignore, .env.local) and extensionless scripts.
        return "config"
    end
    return EXT[ext] or "config"
end

-- classify_path is ~9 pattern matches plus a walk over every path segment, and
-- the sorter re-runs it for every entry on every keystroke over a result set
-- that does not change while a picker is open — so each distinct path is
-- classified once and remembered. Capped rather than unbounded: a long session
-- hopping projects would otherwise hold every path it ever scored.
local MEMO_MAX = 20000
local memo, memo_n = {}, 0

function M.classify(path)
    local hit = memo[path]
    if hit then
        return hit
    end
    local class = classify_path(path)
    if memo_n >= MEMO_MAX then
        memo, memo_n = {}, 0
    end
    memo[path] = class
    memo_n = memo_n + 1
    return class
end

-- Score multiplier for a path. 1.0 = untouched, higher = further down.
function M.penalty(path)
    local class = M.classify(path)
    if class == "source" then
        local langs = M.project_langs()
        local ext = path:lower():match("%.([%w]+)$")
        if next(langs) and not langs[ext] then
            return M.weights.other_source
        end
        return M.weights.source
    end
    return M.weights[class] or M.weights.config
end

-- Wrap a sorter so its scores are scaled by the path's penalty. `path_of`
-- pulls the file path out of the sorted line (the ordinal): the whole line
-- for file pickers, everything before "path:line:col:" for grep.
function M.wrap(sorter, path_of)
    local score = sorter.scoring_function
    sorter.scoring_function = function(self, prompt, line, ...)
        local base = score(self, prompt, line, ...)
        -- -1 is telescope's "discard this entry"; keep it as-is.
        if type(base) ~= "number" or base < 0 then
            return base
        end
        return base * M.penalty(path_of(line))
    end
    return sorter
end

local function whole_line(line)
    return line
end

local function grep_path(line)
    return line:match("^(.-):%d+:%d+:") or line:match("^(.-):%d+:") or line
end

-- Sorter for find_files: fuzzy match quality, scaled by file relevance.
function M.file_sorter(base)
    return M.wrap(base or require("telescope.sorters").get_fuzzy_file(), whole_line)
end

-- Sorter for live_grep. Telescope leaves grep results in ripgrep's order
-- (its sorter only highlights), so the penalty alone decides the order:
-- matches in code float above the same matches in json/markdown, and rows
-- with equal relevance keep ripgrep's original ordering.
function M.grep_sorter()
    return M.wrap(require("telescope.sorters").highlighter_only({}), grep_path)
end

return M
