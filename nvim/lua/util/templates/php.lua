-- Plain PHP scaffolds (no framework). Also shows up alongside Laravel's
-- templates in a Laravel project, since Laravel projects are still PHP —
-- see util/project_stacks.lua.

local php_namespace = require("util.php_namespace")

local M = {}
M.LABEL = "PHP"

local function shell(keyword, class, ns)
    local lines = { "<?php", "" }
    if ns then
        lines[#lines + 1] = "namespace " .. ns .. ";"
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = keyword .. " " .. class
    lines[#lines + 1] = "{"
    lines[#lines + 1] = "}"
    return lines
end

M.KINDS = {
    {
        key = "class",
        label = "Plain class",
        ext = ".php",
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return shell("class", class, ns)
        end,
    },
    {
        key = "interface",
        label = "Interface",
        ext = ".php",
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return shell("interface", class, ns)
        end,
    },
    {
        key = "trait",
        label = "Trait",
        ext = ".php",
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return shell("trait", class, ns)
        end,
    },
}

return M
