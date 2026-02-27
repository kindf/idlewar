local cluster = require "skynet.cluster"
local ProtoMap = require "proto.proto_map"
local Pids = require "proto.pids"
local ProtocolHelper = require "public.protocol_helper"
local ClusterHelper = {}

-- Gate 转发消息
function ClusterHelper.TransmitMessage(connection, protoId, protoMsg)
    local proto = ProtoMap.GetProtoInfo(protoId)
    local node = proto.node
    local service = proto.service or connection.agentAddr
    local succ, err = pcall(cluster.send, node, service, "DispatchClientMessage", connection.fd, protoId, protoMsg)
    return succ, err
end

-- 2M - 4
function ClusterHelper.SendClientMessage(fd, respId, resp)
    local pack = ProtocolHelper.Encode(Pids[respId], resp)
    return pcall(cluster.call, "gatenode", ".gatewatchdog", "SendClientMessage", fd, pack)
end

function ClusterHelper.SendGateNode(service, cmd, ...)
    return pcall(cluster.send, "gatenode", service, cmd, ...)
end

function ClusterHelper.CallGateNode(service, cmd, ...)
    return pcall(cluster.call, "gatenode", service, cmd, ...)
end

function ClusterHelper.CallGameAgentMgr(cmd, ...)
    return pcall(cluster.call, "gamenode", ".agent_mgr", cmd, ...)
end

function ClusterHelper.CallLoginNode(service, cmd, ...)
    return pcall(cluster.call, "loginnode", service, cmd, ...)
end

return ClusterHelper
