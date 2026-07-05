local case = require("util.case")

local M = {}
M.LABEL = "Vue"

M.KINDS = {
    {
        key = "component",
        label = "Single File Component",
        ext = ".vue",
        class_name = function(name)
            return case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return class_name .. ".vue"
        end,
        build = function(class_name)
            return {
                '<script setup lang="ts">',
                "",
                "</script>",
                "",
                "<template>",
                '  <div class="' .. case.kebab_case(class_name) .. '"></div>',
                "</template>",
                "",
                "<style scoped>",
                "</style>",
            }
        end,
    },
    {
        key = "composable",
        label = "Composable",
        ext = ".ts",
        class_name = function(name)
            return "use" .. case.pascal_case(name)
        end,
        filename = function(_, class_name)
            return class_name .. ".ts"
        end,
        build = function(class_name)
            return { "export function " .. class_name .. "() {", "", "}" }
        end,
    },
    {
        key = "store",
        label = "Pinia Store",
        ext = ".ts",
        class_name = function(name)
            local class = case.pascal_case(name)
            if not class:match("Store$") then
                class = class .. "Store"
            end
            return class
        end,
        filename = function(_, class_name)
            return "use" .. class_name .. ".ts"
        end,
        build = function(class_name)
            local base = class_name:gsub("Store$", "")
            local id = case.kebab_case(base)
            return {
                "import { defineStore } from 'pinia';",
                "",
                "export const use" .. base .. "Store = defineStore('" .. id .. "', {",
                "  state: () => ({}),",
                "  actions: {},",
                "});",
            }
        end,
    },
}

return M
