local PlayerBase = {}
local playerData

function PlayerBase.Init(data)
    playerData = data
end

function PlayerBase.GetPlayerData()
    return playerData
end

function PlayerBase.GetUid()
    local data = PlayerBase.GetPlayerData()
    return data.uid
end

function PlayerBase.GetAccount()
    local data = PlayerBase.GetPlayerData()
    return data.account
end

return PlayerBase
