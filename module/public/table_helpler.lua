local TableHelper = {}

function TableHelper.Dump(t, options)
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
            valueStr = TableHelper.Dump(value, {
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
                valueStr = TableHelper.Dump(v, {
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

-- 序列化：将数字键转为字符串键（用于存储到MongoDB）
function TableHelper.SerializeBsonFormat(data, prefix)
    prefix = prefix or "_n_"
    local function process(value, depth)
        -- 基础类型直接返回
        if type(value) ~= "table" then
            return value
        end

        -- 处理表（包含数字键和字符串键）
        local result = {}
        for k, v in pairs(value) do
            local newKey
            local processedValue = process(v, depth + 1)

            if type(k) == "number" then
                -- 数字键添加前缀
                newKey = prefix .. tostring(k)
            elseif type(k) == "string" then
                newKey = k
            elseif type(k) == "boolean" then
                -- 布尔值作为键（特殊情况）
                newKey = "_b_" .. tostring(k)
            else
                -- 其他类型转为字符串
                newKey = "_other_" .. tostring(k)
            end

            result[newKey] = processedValue
        end

        return result
    end

    return process(data, 0)
end

-- 反序列化：将字符串键转回数字键（用于从MongoDB读取）
function TableHelper.DeserializeBsonFormat(data, prefix)
    prefix = prefix or "_n_"
    local function process(value, depth)
        -- 基础类型直接返回
        if type(value) ~= "table" then
            return value
        end

        -- 判断是否是数组
        local isArray = true
        local maxIndex = 0
        for k, _ in pairs(value) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            maxIndex = math.max(maxIndex, k)
        end

        if isArray and maxIndex == #value then
            -- 处理数组
            local result = {}
            for i = 1, #value do
                result[i] = process(value[i], depth + 1)
            end
            return result
        end

        -- 处理普通表
        local result = {}
        for k, v in pairs(value) do
            local newKey
            local processedValue = process(v, depth + 1)

            if type(k) == "string" then
                -- 检查是否为数字键的编码
                local numKey = string.match(k, "^" .. prefix .. "([%d%.]+)$")
                if numKey then
                    -- 尝试转为整数或浮点数
                    local num = tonumber(numKey)
                    if math.floor(num) == num then
                        newKey = math.tointeger(num) or num
                    else
                        newKey = num
                    end
                elseif string.match(k, "^_b_(true|false)$") then
                    -- 布尔键
                    newKey = (string.sub(k, 5) == "true")
                elseif string.match(k, "^_other_") then
                    -- 其他类型的键，保持原样
                    newKey = k
                else
                    -- 普通字符串键
                    newKey = k
                end
            else
                -- 其他类型的键保持不变
                newKey = k
            end

            result[newKey] = processedValue
        end

        return result
    end

    return process(data, 0)
end

-- local test = {
--     account = "test1",
--     uid = 10001,
--     createTime = 1620000000,
--     lastLoginTime = 1620000000,
--     lastLogoutTime = 1620000000,
--     shop = {
--         [1001] = {
--             id = 1001,
--             count = 10,
--             [1] = 1001,
--             [2] = 1002,
--             [3] = 1003
--         },
--         [1002] = {
--             id = 1002,
--             count = 20,
--             [1] = {
--                 [2] = {
--                     [3] = 1003
--                 },
--             },
--         }
--     },
--     arena = {
--         ticket = 10,
--         recoverTs = 1620000000,
--         rank = 1,
--     }
-- }
--
-- local serialized = TableHelper.SerializeBsonFormat(test)
-- local deserialized = TableHelper.DeserializeBsonFormat(serialized)
-- print("serialized:", TableHelper.Dump(serialized))
-- print("deserialized:", TableHelper.Dump(deserialized))

return TableHelper
