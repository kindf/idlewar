local common_util = require "util.common_util"
local rpc = require "user.rpc.main"
local skynet = require "skynet"

local M = {}
function M.handle_c2s_battle(user, _)
    local ret = common_util.cluster_call_battle()
    skynet.error(ret)
    -- rpc.send_s2c_message(user, "battle.s2c_battle", battle_result)
end

function M.handle_c2s_echo(user, msg)
    rpc.send_s2c_message(user, "battle.s2c_echo", {msg = msg})
end

return M
