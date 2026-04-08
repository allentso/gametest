--- 单局状态 - 灵契列表、道具背包
local EventBus = require("systems.EventBus")

local SessionState = {}

SessionState.contracts = {}    -- 已捕获灵契
SessionState.inventory = {}    -- 道具背包
SessionState.resources = {}    -- 本局采集资源
SessionState.stats = {}        -- 统计

function SessionState.reset()
    SessionState.contracts = {}
    SessionState.inventory = {
        sealer_free = 3,    -- 免费素灵符×3
        sealer_t1 = 0,
        sealer_t2 = 0,
        sealer_t3 = 0,
        sealer_t4 = 0,
        traceAsh = 0,       -- 追迹灰
        mirrorSand = 0,     -- 镇灵砂
        soulCharm = 0,      -- 归魂符
    }
    SessionState.resources = {
        lingshi = 0,        -- 灵石
        shouhun = 0,        -- 兽魂
        tianjing = 0,       -- 天晶
    }
    SessionState.stats = {
        beastsCaptured = 0,
        cluesInvestigated = 0,
        resourcesCollected = 0,
    }
end

function SessionState.addContract(contract)
    table.insert(SessionState.contracts, contract)
    SessionState.stats.beastsCaptured = SessionState.stats.beastsCaptured + 1
end

function SessionState.getContracts()
    return SessionState.contracts
end

function SessionState.getContractCount()
    return #SessionState.contracts
end

function SessionState.addItem(itemType, amount)
    amount = amount or 1
    SessionState.inventory[itemType] = (SessionState.inventory[itemType] or 0) + amount
    EventBus.emit("resource_changed", itemType, amount)
end

function SessionState.getItemCount(itemType)
    return SessionState.inventory[itemType] or 0
end

function SessionState.hasItem(itemType)
    return (SessionState.inventory[itemType] or 0) > 0
end

function SessionState.addResource(resType, amount)
    amount = amount or 1
    SessionState.resources[resType] = (SessionState.resources[resType] or 0) + amount
    SessionState.stats.resourcesCollected = SessionState.stats.resourcesCollected + amount
    EventBus.emit("resource_changed", resType, amount)
end

function SessionState.getResource(resType)
    return SessionState.resources[resType] or 0
end

--- 准备封灵器（从全局仓库加载到本局背包）
function SessionState.loadSealers(globalInventory)
    SessionState.inventory.sealer_t2 = globalInventory.sealer_t2 or 0
    SessionState.inventory.sealer_t3 = globalInventory.sealer_t3 or 0
    SessionState.inventory.sealer_t4 = globalInventory.sealer_t4 or 0
end

return SessionState
