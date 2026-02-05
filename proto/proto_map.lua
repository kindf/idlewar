local Pids = require "proto.pids"
local ProtoMap = {}

-- 注册转发到 Login Server 的协议
local function RegisterLoginNodeProto(protoName)
    local protoId = Pids[protoName]
    assert(not ProtoMap[protoId], "重复注册协议号:" .. protoId)
    ProtoMap[protoId] = {
        protoId = protoId,
        protoName = protoName,
        node = "loginnode",
        service = ".login",
    }
end

-- 注册转发到 Game Server 的协议
local function RegisterGameNodeProto(protoName, isAgent)
    local protoId = Pids[protoName]
    assert(not ProtoMap[protoId], "重复注册协议号:" .. protoId)
    ProtoMap[protoId] = {
        protoId = protoId,
        protoName = protoName,
        node = "gamenode",
        service = isAgent and nil or ".agent_mgr",
    }
end

-- 注册 Login Server 的协议
RegisterLoginNodeProto("login.c2s_check_version")
RegisterLoginNodeProto("login.c2s_login_auth")

-- 注册 Game Server 的协议
RegisterGameNodeProto("battle.c2s_battle", false)
RegisterGameNodeProto("battle.c2s_echo", false)
RegisterGameNodeProto("player_base.c2s_login_game", false)

function ProtoMap.GetProtoInfo(protoId)
    return ProtoMap[protoId]
end

return ProtoMap
