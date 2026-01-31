
local RpcHelper = {}
local clientHandler = {}

-- 注册gate转发过来的消息
function RpcHelper.RegisterClientHandler(name, handler)
    assert(type(handler) == "function", "处理函数必须为function")
    assert(not clientHandler[name], "处理函数重复注册 " .. name)
    clientHandler[name] = handler
end

-- 处理有gate转发过来的消息
function RpcHelper.DispatchClientMessage(q, type, ...)
    local handler = clientHandler[type]
    if handler then
        handler(q, ...)
    end
end

function RpcHelper.UnpackHeader(msg)
    local msgId = string.unpack(">I2", msg, 1)
    local buffMsg = msg:sub(3)
    return msgId, buffMsg
end

return RpcHelper
