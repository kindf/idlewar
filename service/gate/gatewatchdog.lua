local skynet = require "skynet"
local socket = require "skynet.socket"
local cluster = require "skynet.cluster"
local CMD = require "gate.gate_msg"

local SOCKET = {}
local clients = {} -- fd -> {agent, addr, uid, agent, acc}
local loginProxy 
local gate

-- 发送消息给客户端
function SendClientByFd(fd, msgtype, data)
    local package = string.pack(">I2", #data) .. data
    socket.write(fd, package)
end

function SendClientByUid(uid, msgtype, data)
end

local function SendLoginProxy(...)
    if not loginProxy then
        loginProxy = cluster.proxy("loginnode", ".loginnode")
    end

    skynet.send(loginProxy, "lua", ...)
end

local function CloseClient(fd, reason)
    local client = clients[fd]
    if client then
        if client.agent then
            skynet.send(client.agent, "lua", "disconnect")
        end
        clients[fd] = nil
        socket.close(fd)
    end
end

local function UnpackMessage(msg, sz)
    local msgId = string.unpack(">I2", msg, 1)
    local data = skynet.unpack(msg, 3)
    return msgId, data
end

-- 消息分发
local function Dispatch(fd, msgId, data)
    local client = clients[fd]
    if not client then
        skynet.error("Unknown client fd:", fd)
        return
    end

    -- 登录请求转发到登录服务
    if msgId == proto.LOGIN then
        SendLoginProxy(fd, data)
        -- 其他消息转发到玩家代理
    elseif client.agent then
        skynet.send(client.agent, "gatenode", msgId, data)
    else
        skynet.send("gamenode", "gatenode", msgId, data)
    end
end

-- 监听新连接
function SOCKET.open(fd, addr)
    print(string.format("New connection: fd=%d, addr=%s", fd, addr))

    clients[fd] = {
        fd = fd,
        addr = addr,
        agent = nil,
    }
end

function SOCKET.data(fd, msg)
    local msgId, data = UnpackMessage(msg)
    Dispatch(fd, msgId, data)
end

function SOCKET.close(fd)
end

function SOCKET.error(fd)
    CloseClient(fd, "SOCKET ERROR")
end

function SOCKET.warning(fd)
    CloseClient(fd, "SOCKET WARNING")
end

function dispatch(c, header, msg)
    if not header or not header.protoid then
        return
    end

    local proto = proto_map.protos[header.protoid]
    if not proto then
        header.errorcode = SYSTEM_ERROR.unknow_proto
        client_msg.send(c.fd, header)
        return
    end
    --print("dispatch proto=", table.tostring(proto))

    if proto.type ~= PROTO_TYPE.C2S then
        header.errorcode = SYSTEM_ERROR.invalid_proto
        client_msg.send(c.fd, header)
        return
    end

    if proto.service and proto.service ~= SERVICE.AUTH and not c.auth_ok then
        header.errorcode = SYSTEM_ERROR.no_auth_account
        client_msg.send(c.fd, header)
        -- print("dispatch proto.service=", proto.service, "c.auth_ok=", c.auth_ok)
        return
    end

    if proto.server == SERVER.GAME and not c.agentnode and not header.roomproxy then
        header.errorcode = SYSTEM_ERROR.unknow_roomproxy
        client_msg.send(c.fd, header)
        return
    end

    if not proto.service and not c.agentnode and not c.agentaddr then
        header.errorcode = SYSTEM_ERROR.no_login_game
        -- print("dispatch proto.service=", proto.service, "c.agentnode=", c.agentnode, "c.agentaddr=", c.agentaddr)
        client_msg.send(c.fd, header)
        return
    end

    local nodename, service
    local target_node
    local ctx = client_msg.get_context(c)

    if proto.service then
        if proto.server == SERVER.GAME then
            nodename = c.agentnode or header.roomproxy
            service = proto.service
        else
            target_node = cluster_monitor.get_cluster_node_by_server(proto.server)
            if not target_node or target_node.is_online == 0 then
                header.errorcode = SYSTEM_ERROR.service_maintance
                client_msg.send(c.fd, header)
                return
            end
            nodename = target_node.nodename
            service = proto.service
        end
    else                 --属于agent或游戏台agent
        if proto.is_agent then --玩家agent,在游戏中则使用游戏agent,否则使用大厅的agent
            if c.agentnode and c.agentver then
                target_node = cluster_monitor.get_cluster_node(c.agentnode)
                if target_node and c.agentver < target_node.ver then
                    c.agentnode = nil
                    c.agentaddr = nil
                    c.agentver = nil
                end
            end
            nodename = c.agentnode or c.hall_agentnode
            service = c.agentaddr or c.hall_agentaddr
        else --游戏台agent
            nodename = c.agentnode or header.roomproxy
            service = c.deskaddr
        end
    end

    if not target_node then
        target_node = cluster_monitor.get_cluster_node(nodename)
    end

    if not target_node or target_node.is_online == 0 then
        header.errorcode = SYSTEM_ERROR.service_maintance
        client_msg.send(c.fd, header)
        return
    end

    local rpc_err = context.rpc_call(nodename, service, "dispatch_client_msg", ctx, msg)
    if rpc_err ~= RPC_ERROR.success then
        header.errorcode = SYSTEM_ERROR.service_stoped
        client_msg.send(c.fd, header)
        return
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
    skynet.register(".gatewatchdog")
end)
