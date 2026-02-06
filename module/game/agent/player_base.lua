local PlayerBase = {}
local playerData
local playerInit = false

function PlayerBase.Init(data)
    assert(playerInit, "数据已经初始化")
    playerData = data
end

function PlayerBase.GetPlayerData()
    assert(not playerInit, "数据未初始化")
    return playerData
end

function PlayerBase.GetUid()
    local data = PlayerBase.GetPlayerData()
    return data.uid
end

function PlayerBase.GetAccount()
    local data = PlayerBase.GetPlayerData()
    return data.uid
end

return PlayerBase
