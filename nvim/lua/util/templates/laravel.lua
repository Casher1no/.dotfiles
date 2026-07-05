-- Laravel-specific PHP scaffolds. Namespace resolves via the project's
-- composer.json PSR-4 map (see util/php_namespace.lua) — Laravel's "App\..."
-- convention is just that project's ordinary PSR-4 entry, nothing special-cased.

local case = require("util.case")
local php_namespace = require("util.php_namespace")

local M = {}
M.LABEL = "Laravel"

local function php_file(ns, uses, class_decl, body_lines)
    local lines = { "<?php", "" }
    if ns then
        lines[#lines + 1] = "namespace " .. ns .. ";"
        lines[#lines + 1] = ""
    end
    for _, use in ipairs(uses or {}) do
        lines[#lines + 1] = "use " .. use .. ";"
    end
    if uses and #uses > 0 then
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = class_decl
    lines[#lines + 1] = "{"
    for _, line in ipairs(body_lines or {}) do
        lines[#lines + 1] = "    " .. line
    end
    lines[#lines + 1] = "}"
    return lines
end

local function with_suffix(suffix)
    return function(name)
        local class = case.pascal_case(name)
        if not class:match(suffix .. "$") then
            class = class .. suffix
        end
        return class
    end
end

M.KINDS = {
    {
        key = "controller",
        label = "Controller",
        ext = ".php",
        class_name = with_suffix("Controller"),
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return php_file(ns, { "Illuminate\\Http\\Request" }, "class " .. class .. " extends Controller", {
                "public function index(Request $request)",
                "{",
                "}",
            })
        end,
    },
    {
        key = "model",
        label = "Model",
        ext = ".php",
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return php_file(ns, { "Illuminate\\Database\\Eloquent\\Model" }, "class " .. class .. " extends Model", {
                "protected $fillable = [];",
            })
        end,
    },
    {
        key = "request",
        label = "Form Request",
        ext = ".php",
        class_name = with_suffix("Request"),
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return php_file(
                ns,
                { "Illuminate\\Foundation\\Http\\FormRequest" },
                "class " .. class .. " extends FormRequest",
                {
                    "public function authorize(): bool",
                    "{",
                    "    return true;",
                    "}",
                    "",
                    "public function rules(): array",
                    "{",
                    "    return [];",
                    "}",
                }
            )
        end,
    },
    {
        key = "middleware",
        label = "Middleware",
        ext = ".php",
        namespace_for = php_namespace.resolve,
        build = function(class, ns)
            return php_file(ns, { "Closure", "Illuminate\\Http\\Request" }, "class " .. class, {
                "public function handle(Request $request, Closure $next)",
                "{",
                "    return $next($request);",
                "}",
            })
        end,
    },
}

return M
