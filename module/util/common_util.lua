local skynet = require "skynet.manager"
local M = {}

function M.abort_new_service(name, ...)
    local ok, ret = pcall(skynet.newservice, name, ...)
    if not ok then
        skynet.error(name, " start error.", ret)
        skynet.sleep(1)
        skynet.abort()
    else
        skynet.error(name, " start...")
    end
    return ret
end

function M.assert_skynet_call(...)
    local ok, err = pcall(...)
    if not ok then
        skynet.error("assert_skynet_call error:", err)
        skynet.sleep(1)
        skynet.abort()
    end
end

local function is_array(table)
    local max = 0
    local count = 0
    for k, _ in pairs(table) do
        if type(k) == "number" then
            if k > max then max = k end
            count = count + 1
        else
            return -1
        end
    end
    if max > count * 2 then
        return -1
    end

    return max
end

local insert = table.insert
function M.serialise_table(value, indent, depth)
    local spacing, spacing2, indent2
    if indent then
        spacing = "\n" .. indent
        spacing2 = spacing .. "  "
        indent2 = indent .. "  "
    else
        spacing, spacing2, indent2 = " ", " ", false
    end
    depth = depth + 1
    if depth > 50 then
        return "Cannot serialise any further: too many nested tables"
    end

    local max = is_array(value)

    local comma = false
    local fragment = { "{" .. spacing2 }
    if max > 0 then
        -- Serialise array
        for i = 1, max do
            if comma then
                insert(fragment, "," .. spacing2)
            end
            insert(fragment, M.dump(value[i], indent2, depth))
            comma = true
        end
    elseif max < 0 then
        -- Serialise table
        for k, v in pairs(value) do
            if comma then
                insert(fragment, "," .. spacing2)
            end
            insert(fragment,
                ("[%s] = %s"):format(M.dump(k, indent2, depth),
                                     M.dump(v, indent2, depth)))
            comma = true
        end
    end
    insert(fragment, spacing .. "}")

    return table.concat(fragment)
end

function M.dump(value, indent, depth)
    if indent == nil then indent = "" end
    if depth == nil then depth = 0 end

    if type(value) == "string" then
        return ("%q"):format(value)
    elseif type(value) == "nil" or type(value) == "number" or
        type(value) == "boolean" then
        return tostring(value)
    elseif type(value) == "table" then
        return M.serialise_table(value, indent, depth)
    else
        return "\"<" .. type(value) .. ">\""
    end
end

return M
