package.path = package.path .. ';./module/battle/?.lua'
local skynet = require "skynet"
require "module.battle.init"
require "module.battle.util.tool"

local attackerHeros = require "module.battle.example.attacker_heros"
local defenderHeros = require "module.battle.example.defender_heros"
local PvpBattle = require "module.battle.battle.pvp_battle"

local function PVPBattle()
    local st = os.clock()
    local id = os.time()
    local battle = PvpBattle.new(15, id)
    -- debug模式
    battle:SetDebugger()
    battle:SetCamp(1, 2)
    battle:SetAttackerHeroList(attackerHeros)
    battle:SetDefenderHeroList(defenderHeros)
    battle:Init()
    battle:Run()
    local frameActionList = battle.context.frameActionList
    local isWin = battle:IsWin()
    battle:Destroy()
    local et = os.clock()
    return {isWin = isWin, frameActionList = frameActionList, costTime = et - st}
end

local CMD = {}
function CMD.pvp_battle()
    return PVPBattle()
end

skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        local f = CMD[command]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error("invalid cmd. cmd:%s", command)
        end
    end)
end)
