local skynet = require "skynet"
local cluster = require "skynet.cluster"
local ProtoMap = require "proto.proto_map"
local ClusterHelper = {}

function ClusterHelper.GetNodeName()
    return skynet.getenv("nodename")
end

function ClusterHelper.GetNodeByServer(server)
end

-- Gate 转发消息
function ClusterHelper.TransmitMessage(connection, protoId, protoMsg)
    local proto = ProtoMap.GetProtoInfo(protoId)
    local node = proto.node
    local service = proto.service or connection.agent
    local succ, err = pcall(cluster.send, node, service, "client", protoId, protoMsg)
    return succ, err
end

return ClusterHelper
