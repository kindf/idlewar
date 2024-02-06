local battle_model = require "user.battle.battle_model"
local const_battle = require "user.battle.const"
local random_util = require "util.random_util"
local user_message= require "user.user_message"
local skynet = require "skynet"

local M = {}

local function battle_turn(atk, def)
    local hit = const_battle.DEFAULT_HIT_RATE
        if (atk:get_level() ~= def:get_level()) then
            hit = hit + (atk:get_level() - def:get_level()) * const_battle.LEVEL_HIT_FACTOR
        end

        if (atk:get_total_dex() ~= def:get_total_dex()) then
            hit = hit + (atk:get_total_dex() - def:get_total_dex()) * const_battle.DEX_HIT_FACTOR
        end

        local actType
        local damage = 0
        if hit >= const_battle.TOTAL_HIT_RATE then
            -- 必定命中
            actType = const_battle.BATTLE_ACT_TYPE.HIT;
            damage = random_util.random_number(1, atk:get_total_str() + 1)
        elseif hit <= 0 then
            -- 必定MISS
            actType = const_battle.BATTLE_ACT_TYPE.MISS;
        else
            -- Roll点
            local roll = random_util.random_number(1, 10000);
            if roll <= hit then
                -- 命中
                actType = const_battle.BATTLE_ACT_TYPE.HIT;
                damage = random_util.random_number(1, atk:get_total_str() + 1);
            else
                -- MISS
                actType = const_battle.BATTLE_ACT_TYPE.MISS;
            end
        end

        def:take_damage(damage);
        return {
            act_type = actType,
            damage = damage,
        }
end

function M.client_call_battle(user, _)
    local round = 1
    local total_seq = 0
    local total_round = 1
    local str_exp = 0
    local dex_exp = 0
    local atk_model = battle_model.from_player()
    local def_model = battle_model.from_mob()
    local battle_result_code = const_battle.BATTLE_RESULT_CODE.DRAW
    local battle_result = {
        total_round = 0,
        total_seq = 0,
        battle_result_code = const_battle.BATTLE_RESULT_CODE.DRAW,
        battle_logs = {}
    }
    while (round <= const_battle.MAX_ROUND) do
        total_round = round

        local atk_turn_result = battle_turn(atk_model, def_model)
        str_exp = str_exp + atk_turn_result.damage
        total_seq = total_seq + 1
        table.insert(battle_result.battle_logs, {
            seq_number = total_seq,
            round = round,
            atk_hp = atk_model:get_total_hp(),
            def_hp = def_model:get_total_hp(),
            act_type = atk_turn_result.act_type,
            damage = atk_turn_result.damage,
        })
        skynet.error(string.format("我方：\n当前回合：%s, 我方生命：%s, 敌方生命：%s, 动作类型：%s, 伤害：%s\n", round, atk_model:get_total_hp(), def_model:get_total_hp(), atk_turn_result.act_type, atk_turn_result.damage))
        if (def_model:is_defeat()) then
            break
        end

        local def_turn_resule = battle_turn(def_model, atk_model)
        total_seq = total_seq + 1
        table.insert(battle_result.battle_logs, {
            seq_number = total_seq,
            round = round,
            atk_hp = def_model:get_total_hp(),
            def_hp = atk_model:get_total_hp(),
            act_type = def_turn_resule.act_type,
            damage = def_turn_resule.damage,
        })
        skynet.error(string.format("敌方：\n当前回合：%s, 我方生命：%s, 对方生命：%s, 动作类型：%s, 伤害：%s\n", round, def_model:get_total_hp(), atk_model:get_total_hp(), atk_turn_result.act_type, atk_turn_result.damage))
        dex_exp = dex_exp + def_turn_resule.damage
        if (atk_model:is_defeat()) then
            battle_result_code = const_battle.BATTLE_RESULT_CODE.LOSE
            break
        end

        round = round + 1
    end

    battle_result.total_round = total_round
    battle_result.total_seq = total_seq
    battle_result.battle_result_code = battle_result_code

    -- local table_util = require "util.table_util"
    -- local skynet = require "skynet"
    -- skynet.error(table_util.dump(battle_result))
    user_message.send_client_msg(user, battle_result)
end

return M
