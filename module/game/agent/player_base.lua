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

return PlayerBase
