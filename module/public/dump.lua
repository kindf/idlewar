-- 综合版：最实用的 table 打印函数
function table.dump(t, options)
    options = options or {}
    local indent = options.indent or 0
    local maxDepth = options.maxDepth or 50
    local visited = options.visited or {}
    local currentDepth = options.currentDepth or 0

    if currentDepth > maxDepth then
        return "..."
    end

    if type(t) ~= "table" then
        if type(t) == "string" then
            return string.format("%q", t)
        else
            return tostring(t)
        end
    end

    -- 检测循环引用
    if visited[t] then
        return "<循环引用>"
    end
    visited[t] = true

    local result = {}
    local spaces = string.rep("  ", indent)
    table.insert(result, "{\n")

    -- 收集所有键值对
    local items = {}

    -- 数组部分（有序）
    for i = 1, #t do
        local value = t[i]
        local keyStr = "[" .. i .. "]"
        local valueStr
        if type(value) == "table" then
            valueStr = table.dump(value, {
                indent = indent + 1,
                maxDepth = maxDepth,
                visited = visited,
                currentDepth = currentDepth + 1
            })
        else
            valueStr = type(value) == "string" and string.format("%q", value) or tostring(value)
        end
        table.insert(items, spaces .. "  " .. keyStr .. " = " .. valueStr)
    end

    -- 键值对部分
    for k, v in pairs(t) do
        if type(k) ~= "number" or k > #t or k < 1 then
            local keyStr = type(k) == "string" and k or "[" .. tostring(k) .. "]"
            local valueStr
            if type(v) == "table" then
                valueStr = table.dump(v, {
                    indent = indent + 1,
                    maxDepth = maxDepth,
                    visited = visited,
                    currentDepth = currentDepth + 1
                })
            else
                valueStr = type(v) == "string" and string.format("%q", v) or tostring(v)
            end
            table.insert(items, spaces .. "  " .. keyStr .. " = " .. valueStr)
        end
    end

    table.insert(result, table.concat(items, ",\n"))
    table.insert(result, "\n" .. spaces .. "}")

    visited[t] = nil
    return table.concat(result)
end

