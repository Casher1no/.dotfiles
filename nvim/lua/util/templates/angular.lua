local case = require("util.case")

local M = {}
M.LABEL = "Angular"

local function make_kind(suffix, label, build_body)
    return {
        key = suffix:lower(),
        label = label,
        ext = ".ts",
        class_name = function(name)
            local class = case.pascal_case(name)
            if not class:match(suffix .. "$") then
                class = class .. suffix
            end
            return class
        end,
        filename = function(name, class_name)
            local base = case.kebab_case((name:gsub(suffix .. "$", "")))
            if base == "" then
                base = case.kebab_case((class_name:gsub(suffix .. "$", "")))
            end
            return base .. "." .. suffix:lower() .. ".ts"
        end,
        build = function(class_name)
            return build_body(class_name)
        end,
    }
end

M.KINDS = {
    make_kind("Component", "Component", function(class_name)
        local selector = case.kebab_case((class_name:gsub("Component$", "")))
        return {
            "import { Component } from '@angular/core';",
            "",
            "@Component({",
            "  selector: 'app-" .. selector .. "',",
            "  templateUrl: './" .. selector .. ".component.html',",
            "  styleUrl: './" .. selector .. ".component.scss',",
            "})",
            "export class " .. class_name .. " {",
            "}",
        }
    end),
    make_kind("Service", "Service", function(class_name)
        return {
            "import { Injectable } from '@angular/core';",
            "",
            "@Injectable({",
            "  providedIn: 'root',",
            "})",
            "export class " .. class_name .. " {",
            "}",
        }
    end),
    make_kind("Module", "Module", function(class_name)
        return {
            "import { NgModule } from '@angular/core';",
            "",
            "@NgModule({",
            "  declarations: [],",
            "  imports: [],",
            "})",
            "export class " .. class_name .. " {",
            "}",
        }
    end),
    make_kind("Directive", "Directive", function(class_name)
        local selector = case.pascal_case((class_name:gsub("Directive$", "")))
        return {
            "import { Directive } from '@angular/core';",
            "",
            "@Directive({",
            "  selector: '[app" .. selector .. "]',",
            "})",
            "export class " .. class_name .. " {",
            "}",
        }
    end),
    make_kind("Pipe", "Pipe", function(class_name)
        local pipe_name = (case.kebab_case((class_name:gsub("Pipe$", "")))):gsub("%-", "")
        return {
            "import { Pipe, PipeTransform } from '@angular/core';",
            "",
            "@Pipe({",
            "  name: '" .. pipe_name .. "',",
            "})",
            "export class " .. class_name .. " implements PipeTransform {",
            "  transform(value: unknown): unknown {",
            "    return value;",
            "  }",
            "}",
        }
    end),
}

return M
