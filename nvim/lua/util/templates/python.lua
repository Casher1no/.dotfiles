local case = require("util.case")

local M = {}
M.LABEL = "Python"

M.KINDS = {
    {
        key = "module",
        label = "Module (functions)",
        ext = ".py",
        class_name = function(name)
            return name
        end,
        filename = function(_, class_name)
            return case.snake_case(class_name) .. ".py"
        end,
        build = function()
            return { "" }
        end,
    },
    {
        key = "class",
        label = "Class",
        ext = ".py",
        class_name = function(name)
            return case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return case.snake_case(class_name) .. ".py"
        end,
        build = function(class_name)
            return {
                "class " .. class_name .. ":",
                "    def __init__(self):",
                "        pass",
            }
        end,
    },
}

return M
