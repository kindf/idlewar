local cluster = require "skynet.cluster"
local ProtoMap = require "proto.proto_map"
local Pb = require "pb"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local ClusterHelper = {}

-- Gate 转发消息
function ClusterHelper.TransmitMessage(connection, protoId, protoMsg)
    local proto = ProtoMap.GetProtoInfo(protoId)
    local node = proto.node
    local service = proto.service or connection.agentaddr
    local succ, err = pcall(cluster.send, node, service, "DispatchClientMessage", connection.fd, protoId, protoMsg)
    return succ, err
end

local spack = string.pack
-- 2M - 4
local lenLimit = 65535 - 4
function ClusterHelper.SendClientMessage(fd, respId, resp)
    local ret, msg = pcall(Pb.encode, Pids[respId], resp)
    if not ret then
        return Logger.Error("消息编码失败 err:%s", msg)
    end
    local bodyLen = #msg
    assert(bodyLen <= lenLimit, "消息长度超出限制")
    local pack = spack(">h c"..bodyLen, respId, msg)
    return pcall(cluster.send, "gatenode", ".gatewatchdog", "SendClientMessage", fd, pack)
end

return ClusterHelper
