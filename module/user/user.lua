local M = {}

local user = {}
user.__index = user

local function new_user_data()
    local o = {
        acc = "",
        uid = 0,
        msg_cnt = 0,
        fight_data = {},
    }
    return o
end

function M.new()
    local o = new_user_data()
    setmetatable(o, user)
    return o
end

function user:init(data)
    self.acc = data.acc
    self.uid = data.uid
    self:init_msg(data)
    self:init_fight(data)
end

function user:init_msg(data)
    self.msg_cnt = data.msg_cnt or 0
end

function user:init_fight(data)
    for _, v in pairs(data.fight_data or {}) do
        self.fight_data[v.id] = v
    end
end

return M
