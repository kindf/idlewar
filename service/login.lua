local skynet = require "skynet"
local netpack = require "skynet.netpack"

local CMD = {}

--登录状态
local fd2LoginState = {
    -- [fd] = {
    --     state = xxx, -- 状态
    --     token = xxx, -- token
    --     timeout = xxx -- 超时
    -- },
}
local LOGIN_CHECK_AUTH_STATE = 1
local LOGIN_SUCCESS_STATE = 2

--检查账号是否已经登录
function CMD.CheckAccountLogin(fd, token)
    local fdLoginState = fd2LoginState[fd]
    if not fdLoginState then
        return false
    end
    if fdLoginState.state ~= LOGIN_SUCCESS_STATE then
        return false
    end
    if fdLoginState.timeout < os.time() then
        fdLoginState[fd] = nil
        return false
    end
    if fdLoginState.token == token then
        fdLoginState[fd] = nil
        return true
    end
    return false
end

--检查版本
local function CheckVersion(fd, version)
    local fdLoginState = fd2LoginState[fd]
    if fdLoginState then
        return false
    end
    -- 版本检查
    if version then
        fd2LoginState[fd] = { state = LOGIN_CHECK_AUTH_STATE, token = nil, timeout = nil}
        return true
    end
    return false
end
RpcHelper.Register("login", "CheckVersion", CheckVersion)

--登录认证
function CMD.CheckAuth(fd, token)
    local fdLoginState = fd2LoginState[fd]
    if not fdLoginState then
        return false
    end
    if fdLoginState.state ~= LOGIN_CHECK_AUTH_STATE then
        return false
    end
    -- TODO: sdk token认证 && 生成新的服务器token
    fdLoginState.state = LOGIN_SUCCESS_STATE
    fdLoginState.token = token
    fdLoginState.timeout = os.time() + 300
    return true
end

local function Dispatch(fd, msgId, msgBody)
    local msgName = PBMap[msgId]
    assert(msgName)
    local pbMsg = protobuf.decode(msgName, msgBody)

    return msgIdx, msgName, pbMsg, netMsg
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd == "socket" then
            Dispatch(cmd, subcmd, ...)
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
end)
