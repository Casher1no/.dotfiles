-- File/folder/filetype icons with wider coverage than nvim-web-devicons
-- (resolves by filetype, not just extension, and has directory + special-file
-- icon sets). mock_nvim_web_devicons() impersonates the nvim-web-devicons
-- API, so neo-tree, telescope, lualine and trouble use these icons without
-- any of them being configured for it — the real nvim-web-devicons is no
-- longer installed.
-- https://github.com/echasnovski/mini.icons
return {
    "echasnovski/mini.icons",
    lazy = true,
    opts = function()
        -- Folder-variant icons (same folder silhouette with a purpose badge)
        -- for common folder names. Matching is by exact name, so add()
        -- registers each spelling plus its Capitalized form.
        local directory = {}
        local function add(spec, ...)
            for _, name in ipairs({ ... }) do
                directory[name] = spec
                directory[name:sub(1, 1):upper() .. name:sub(2)] = spec
            end
        end

        -- Domain layers
        add({ glyph = "󱁿", hl = "MiniIconsCyan" }, "service", "services")
        add({ glyph = "󱋣", hl = "MiniIconsGreen" }, "repository", "repositories", "db", "database", "data")
        add({ glyph = "󰉗", hl = "MiniIconsOrange" }, "factory", "factories")
        add({ glyph = "󰾶", hl = "MiniIconsPurple" }, "dto", "dtos")
        add({ glyph = "󱉭", hl = "MiniIconsRed" }, "entity", "entities")
        add({ glyph = "󱋤", hl = "MiniIconsGreen" }, "model", "models")
        add({ glyph = "󱧺", hl = "MiniIconsGreen" }, "handler", "handlers", "listener", "listeners")
        add({ glyph = "󱧮", hl = "MiniIconsBlue" }, "command", "commands")
        add({ glyph = "󱧱", hl = "MiniIconsOrange" }, "request", "requests", "response", "responses")
        add({ glyph = "󱧬", hl = "MiniIconsPurple" }, "controller", "controllers")
        add({ glyph = "󱂷", hl = "MiniIconsAzure" }, "type", "types", "interface", "interfaces", "contracts")
        add({ glyph = "󰪺", hl = "MiniIconsGrey" }, "cache", "tmp", "temp")
        add({ glyph = "󰅩", hl = "MiniIconsBlue" }, "component", "components")
        add({ glyph = "󰕰", hl = "MiniIconsPurple" }, "ui", "widgets")
        add({ glyph = "󰚀", hl = "MiniIconsAzure" }, "element", "elements")
        add({ glyph = "󰐩", hl = "MiniIconsRed" }, "directive", "directives")
        add({ glyph = "󰈬", hl = "MiniIconsGreen" }, "page", "pages", "views", "screens")
        add({ glyph = "󰟥", hl = "MiniIconsYellow" }, "pipe", "pipes")
        add({ glyph = "󰃭", hl = "MiniIconsYellow" }, "event", "events")
        add({ glyph = "󰠮", hl = "MiniIconsGreen" }, "record", "records")
        add({ glyph = "󰏗", hl = "MiniIconsOrange" }, "installer", "installers")
        add({ glyph = "󰒓", hl = "MiniIconsCyan" }, "manager", "managers")
        add({ glyph = "󰷈", hl = "MiniIconsPurple" }, "editor", "editors")
        add({ glyph = "󰌌", hl = "MiniIconsRed" }, "input", "inputs")
        add({ glyph = "󱂀", hl = "MiniIconsRed" }, "di", "injection")
        add({ glyph = "󰏿", hl = "MiniIconsBlue" }, "constant", "constants")
        add({ glyph = "󰆍", hl = "MiniIconsGrey" }, "console")
        add({ glyph = "", hl = "MiniIconsYellow" }, "enum", "enums")
        add({ glyph = "󱐋", hl = "MiniIconsRed" }, "exception", "exceptions")
        add({ glyph = "󰕥", hl = "MiniIconsCyan" }, "policy", "policies")
        add({ glyph = "󰏓", hl = "MiniIconsOrange" }, "provider", "providers")
        directory.DTO = directory.dto
        directory.DTOs = directory.dto
        directory.DI = directory.di
        directory.UI = directory.ui

        -- General purpose
        add({ glyph = "󱥾", hl = "MiniIconsGreen" }, "test", "tests", "spec", "specs", "__tests__")
        add({ glyph = "󱧼", hl = "MiniIconsOrange" }, "util", "utils", "utility", "utilities", "helper", "helpers", "tools")
        add({ glyph = "󱁽", hl = "MiniIconsPurple" }, "config", "configs", "settings", "conf")
        add({ glyph = "󰙞", hl = "MiniIconsGreen" }, "environment", "environments", "env", "envs")
        add({ glyph = "󰉕", hl = "MiniIconsGreen" }, "common", "commons", "shared")
        add({ glyph = "󰲁", hl = "MiniIconsOrange" }, "webhook", "webhooks")
        add({ glyph = "󰲂", hl = "MiniIconsAzure" }, "doc", "docs")
        add({ glyph = "󰲃", hl = "MiniIconsGrey" }, "log", "logs", "logger", "loggers")
        add({ glyph = "󰉓", hl = "MiniIconsBlue" }, "asset", "assets", "resources", "static")
        add({ glyph = "󰭃", hl = "MiniIconsPurple" }, "style", "styles", "css", "scss", "sass", "themes")
        add({ glyph = "󰉏", hl = "MiniIconsPurple" }, "image", "images", "img", "icons")
        add({ glyph = "󱍙", hl = "MiniIconsCyan" }, "audio", "sounds", "music")
        add({ glyph = "󰢬", hl = "MiniIconsYellow" }, "auth", "security")
        add({ glyph = "󰉐", hl = "MiniIconsRed" }, "secret", "secrets", "private")
        add({ glyph = "󰉌", hl = "MiniIconsBlue" }, "user", "users", "profile", "profiles", "account", "accounts")
        add({ glyph = "󰡰", hl = "MiniIconsPurple" }, "api", "network", "http", "connection")
        add({ glyph = "󰠅", hl = "MiniIconsCyan" }, "gateway", "gateways", "proxy", "proxies")
        add({ glyph = "󰍛", hl = "MiniIconsBlue" }, "core", "main", "_Core", "_core")
        add({ glyph = "󰚝", hl = "MiniIconsYellow" }, "feature", "features", "module", "modules")
        add({ glyph = "󰙅", hl = "MiniIconsRed" }, "state", "store", "stores", "reducers", "actions")
        add({ glyph = "󰴋", hl = "MiniIconsCyan" }, "migration", "migrations", "sync")
        add({ glyph = "󰷌", hl = "MiniIconsOrange" }, "notification", "notifications", "alerts")
        add({ glyph = "󰉍", hl = "MiniIconsGreen" }, "download", "downloads")
        add({ glyph = "󰉙", hl = "MiniIconsAzure" }, "upload", "uploads")
        add({ glyph = "󰛫", hl = "MiniIconsGrey" }, "archive", "backup", "zip")
        add({ glyph = "󰀻", hl = "MiniIconsBlue" }, "app", "apps")
        add({ glyph = "󰆦", hl = "MiniIconsOrange" }, "storage")
        add({ glyph = "󰄄", hl = "MiniIconsPurple" }, "framework", "frameworks", "vendor")
        add({ glyph = "󱊰", hl = "MiniIconsRed" }, "route", "routes", "routing")
        add({ glyph = "󰞉", hl = "MiniIconsGreen" }, "public", "www", "web")
        add({ glyph = "󰛖", hl = "MiniIconsRed" }, "font", "fonts")
        add({ glyph = "󰗊", hl = "MiniIconsAzure" }, "i18n", "locale", "locales", "lang", "translations")
        add({ glyph = "󰆓", hl = "MiniIconsGreen" }, "save", "saves", "savedata", "savegame", "savegames")
        add({ glyph = "󰐱", hl = "MiniIconsPurple" }, "extension", "extensions")
        add({ glyph = "", hl = "MiniIconsYellow" }, "process", "processes")
        add({ glyph = "󰔟", hl = "MiniIconsCyan" }, "timer", "timers")
        add({ glyph = "󰓹", hl = "MiniIconsAzure" }, "attribute", "attributes")
        add({ glyph = "󰄀", hl = "MiniIconsBlue" }, "camera", "cameras")
        add({ glyph = "󰚥", hl = "MiniIconsGreen" }, "plugin", "plugins")

        return { directory = directory }
    end,
    config = function(_, opts)
        require("mini.icons").setup(opts)

        -- Pin icon colors so switching themes doesn't recolor them. Every
        -- colorscheme (and mini.icons itself) redefines the MiniIcons*
        -- groups from its own palette; overriding them here — and again on
        -- each ColorScheme — keeps icons at these fixed (catppuccin-mocha)
        -- colors everywhere they're used (explorer, telescope, lualine, …).
        local icon_colors = {
            MiniIconsAzure = "#74c7ec",
            MiniIconsBlue = "#89b4fa",
            MiniIconsCyan = "#94e2d5",
            MiniIconsGreen = "#a6e3a1",
            MiniIconsGrey = "#9399b2",
            MiniIconsOrange = "#fab387",
            MiniIconsPurple = "#cba6f7",
            MiniIconsRed = "#f38ba8",
            MiniIconsYellow = "#f9e2af",
        }
        local function pin_icon_colors()
            for group, fg in pairs(icon_colors) do
                vim.api.nvim_set_hl(0, group, { fg = fg })
            end
        end
        pin_icon_colors()
        vim.api.nvim_create_autocmd("ColorScheme", {
            group = vim.api.nvim_create_augroup("fixed_icon_colors", { clear = true }),
            callback = pin_icon_colors,
        })
    end,
    init = function()
        -- Any require("nvim-web-devicons") resolves to the mini.icons mock.
        -- package.preload runs before the runtime path is searched, so this
        -- works even while mini.icons itself is still lazy-loaded.
        package.preload["nvim-web-devicons"] = function()
            require("mini.icons").mock_nvim_web_devicons()
            return package.loaded["nvim-web-devicons"]
        end
    end,
}
