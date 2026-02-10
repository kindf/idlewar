local Define = {}

-- agent 状态
Define.AGENT_STATE = {
    ONLINE_AGENT_STATE = 1, -- 在线
    OFFLINE_AGENT_STATE = 2, -- 离线
}

Define.AGENT_SAVE_INTERVAL = 10

Define.CONNECTION_STATUS = {
    CONNECTED = 1,
    LOGINING = 2,
    AUTHED = 3,
    GAMING = 4,
}

return Define
