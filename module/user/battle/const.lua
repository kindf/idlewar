local M = {}

--最大回合数
M.MAX_ROUND = 3
--默认命中率
M.DEFAULT_HIT_RATE = 9000
--总命中率
M.TOTAL_HIT_RATE = 10000
--等级差值命中系数
M.LEVEL_HIT_FACTOR = 100
--敏捷差值命中系数
M.DEX_HIT_FACTOR = 10

M.BATTLE_RESULT_CODE = {
    WIN = 1,
    LOST = 2,
    DRAW = 3,
}

--战斗动作类型
M.BATTLE_ACT_TYPE = {
    HIT = 1,
    MISS = 2,
}

return M
