local M = {}

function M.str2table(str)
    if str == nil or type(str) ~= "string" then
        return
    end
    return load("return "..str)()
end

function M.table2str(t)
    local function sub_func(value)
        if type(value)=='table' then
            return M.table2str(value)
        elseif type(value)=='string' then
            return "\'"..value.."\'"
        else
            return tostring(value)
        end
    end
    if t == nil then return "" end
    local retstr= "{"

    local i = 1
    for key,value in pairs(t) do
        local signal = ","
        if i==1 then
          signal = ""
        end

        if key == i then
            retstr = retstr..signal..sub_func(value)
        else
            if type(key)=='number' or type(key) == 'string' then
                retstr = retstr..signal..'['..sub_func(key).."]="..sub_func(value)
            else
                if type(key)=='userdata' then
                    retstr = retstr..signal.."*s"..M.table2str(getmetatable(key)).."*e".."="..sub_func(value)
                else
                    retstr = retstr..signal..key.."="..sub_func(value)
                end
            end
        end

        i = i+1
    end

     retstr = retstr.."}"
     return retstr
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
