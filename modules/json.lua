local json = {}

local function decode_value(text, index)
    while text:sub(index, index):match("%s") do index = index + 1 end
    local character = text:sub(index, index)
    if character == "{" then
        local object = {}
        index = index + 1
        while true do
            while text:sub(index, index):match("%s") do index = index + 1 end
            if text:sub(index, index) == "}" then return object, index + 1 end
            local key
            key, index = decode_value(text, index)
            assert(key ~= nil, "JSON object keys cannot be null")
            while text:sub(index, index):match("%s") do index = index + 1 end
            assert(text:sub(index, index) == ":", "Expected ':' in JSON object")
            local value
            value, index = decode_value(text, index + 1)
            object[key] = value
            while text:sub(index, index):match("%s") do index = index + 1 end
            if text:sub(index, index) == "}" then return object, index + 1 end
            assert(text:sub(index, index) == ",", "Expected ',' in JSON object")
            index = index + 1
        end
    elseif character == "[" then
        local array = {}
        index = index + 1
        while true do
            while text:sub(index, index):match("%s") do index = index + 1 end
            if text:sub(index, index) == "]" then return array, index + 1 end
            local value
            value, index = decode_value(text, index)
            array[#array + 1] = value
            while text:sub(index, index):match("%s") do index = index + 1 end
            if text:sub(index, index) == "]" then return array, index + 1 end
            assert(text:sub(index, index) == ",", "Expected ',' in JSON array")
            index = index + 1
        end
    elseif character == '"' then
        local end_index = index + 1
        while text:sub(end_index, end_index) ~= '"' do
            if text:sub(end_index, end_index) == "\\" then end_index = end_index + 1 end
            end_index = end_index + 1
        end
        local value = text:sub(index + 1, end_index - 1):gsub('\\"', '"'):gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t'):gsub('\\\\', '\\')
        return value, end_index + 1
    else
        local end_index = index
        while end_index <= #text and not text:sub(end_index, end_index):match("[%s,%]}]") do end_index = end_index + 1 end
        local literal = text:sub(index, end_index - 1)
        if literal == "true" then return true, end_index end
        if literal == "false" then return false, end_index end
        if literal == "null" then return nil, end_index end
        return tonumber(literal), end_index
    end
end

function json.decode(text)
    local value, index = decode_value(text, 1)
    while text:sub(index, index):match("%s") do index = index + 1 end
    assert(index > #text, "Unexpected trailing JSON data")
    return value
end

return json
