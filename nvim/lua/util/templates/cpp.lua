local case = require("util.case")

local M = {}
M.LABEL = "C++"

-- LeetCode hands you a `class Solution` with one method and runs its own
-- driver; locally you need a main() to call it with. The template ships both,
-- so a new file is runnable with <F8> the moment it's written.
local function leetcode(class_name)
    return {
        "#include <bits/stdc++.h>",
        "",
        "using namespace std;",
        "",
        "// " .. class_name,
        "class Solution {",
        "public:",
        "    ",
        "};",
        "",
        "int main() {",
        "    ios_base::sync_with_stdio(false);",
        "    cin.tie(nullptr);",
        "",
        "    Solution solution;",
        "",
        "    return 0;",
        "}",
    }
end

M.KINDS = {
    {
        key = "leetcode",
        label = "LeetCode solution",
        ext = ".cpp",
        class_name = function(name)
            return case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return case.snake_case(class_name) .. ".cpp"
        end,
        build = leetcode,
    },
    {
        key = "source",
        label = "Source file",
        ext = ".cpp",
        class_name = function(name)
            return case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return case.snake_case(class_name) .. ".cpp"
        end,
        build = function()
            return {
                "#include <iostream>",
                "",
                "int main() {",
                "    ",
                "    return 0;",
                "}",
            }
        end,
    },
    {
        key = "header",
        label = "Header + class",
        ext = ".hpp",
        class_name = function(name)
            return case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return case.snake_case(class_name) .. ".hpp"
        end,
        build = function(class_name)
            return {
                "#pragma once",
                "",
                "class " .. class_name .. " {",
                "public:",
                "    " .. class_name .. "() = default;",
                "",
                "private:",
                "    ",
                "};",
            }
        end,
    },
}

return M
