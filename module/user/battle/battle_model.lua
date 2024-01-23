local M = {}

local model = {}
model.__index = model

function model:get_total_hp()
    local total_hp = self.hp + self.add_hp
    return math.max(0, total_hp)
end

function model:get_total_str()
    return self.str + self.add_str
end

function model:get_total_dex()
    return self.dex + self.add_dex
end

function model:get_total_wit()
    return self.wit + self.add_wit
end

function model:get_level()
    return self.level
end

function model:take_damage(damage)
    self.hp = self.hp - damage
end

function model:is_defeat()
    return self:get_total_hp() <= 0
end

function M.from_player()
    return M.new("player", 20, 1000, 0, 10, 0, 100, 0, 10, 0)
end

function M.from_mob()
    return M.new("monster", 10, 800, 0, 5, 0, 100, 0, 5, 0)
end

function M.new(name, level, hp, str, dex, wit, add_hp, add_str, add_dex, add_wit)
    local o = {
        name = name,
        level = level,
        hp = hp,
        str = str,
        dex = dex,
        wit = wit,
        add_hp = add_hp,
        add_str = add_str,
        add_dex = add_dex,
        add_wit = add_wit,
    }
    setmetatable(o, model)
    return o
end

return M
