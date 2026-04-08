--- 全局状态管理 + 存档读写（跨局持久数据）
local SaveGuard = require("systems.SaveGuard")
local Config = require("Config")

local GameState = {}

-- 持久数据默认值
local DEFAULT_DATA = {
    -- 仓库资源
    lingshi = 0,       -- 灵石
    shouhun = 0,       -- 兽魂
    tianjing = 0,      -- 天晶

    -- 封灵器库存
    sealer_t2 = 0,     -- 青玉壶
    sealer_t3 = 0,     -- 金缕珠
    sealer_t4 = 0,     -- 天命盘

    -- 图鉴
    bestiary = {},     -- { [beastId] = { discovered=bool, captured=bool, count=0, bestQuality="" } }

    -- 统计
    totalExplorations = 0,
    totalCaptures = 0,
    totalEvacuations = 0,

    -- 每日
    loginDays = 0,
    lastLoginDate = "",
    dailyClaimed = {},

    -- 教学
    tutorialDone = false,
}

--- 当前游戏数据
GameState.data = {}

--- 深拷贝默认值
local function deepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- 初始化/加载存档
function GameState.init()
    local saved = SaveGuard.load("saves/main.json", Config.DEVICE_ID)
    if saved then
        GameState.data = saved
        for k, v in pairs(DEFAULT_DATA) do
            if GameState.data[k] == nil then
                if type(v) == "table" then
                    GameState.data[k] = deepCopy(v)
                else
                    GameState.data[k] = v
                end
            end
        end
        print("[GameState] 存档加载成功")
    else
        GameState.data = deepCopy(DEFAULT_DATA)
        print("[GameState] 新存档已创建")
    end

    local PitySystem = require("systems.PitySystem")
    PitySystem.load()
end

--- 保存到磁盘
function GameState.save()
    SaveGuard.save("saves/main.json", GameState.data, Config.DEVICE_ID)
    print("[GameState] 存档已保存")
end

--- 添加资源
function GameState.addResource(resType, amount)
    amount = amount or 1
    GameState.data[resType] = (GameState.data[resType] or 0) + amount
end

--- 获取资源
function GameState.getResource(resType)
    return GameState.data[resType] or 0
end

--- 消耗资源
function GameState.spendResource(resType, amount)
    local current = GameState.data[resType] or 0
    if current < amount then return false end
    GameState.data[resType] = current - amount
    return true
end

--- 记录图鉴
function GameState.recordBeast(beastId, quality)
    if not beastId then
        print("[GameState] recordBeast: beastId is nil, skipping")
        return
    end
    if not GameState.data.bestiary[beastId] then
        GameState.data.bestiary[beastId] = {
            discovered = true,
            captured = false,
            count = 0,
            bestQuality = "",
            qualities = { R = 0, SR = 0, SSR = 0 },
        }
    end
    local entry = GameState.data.bestiary[beastId]
    entry.discovered = true
    entry.captured = true
    entry.count = entry.count + 1
    -- 兼容旧存档：补充 qualities 字段
    if not entry.qualities then
        entry.qualities = { R = 0, SR = 0, SSR = 0 }
    end
    -- 分品质计数
    local q = quality or "R"
    entry.qualities[q] = (entry.qualities[q] or 0) + 1
    -- 更新最佳品质
    local qualRank = { R = 1, SR = 2, SSR = 3 }
    if (qualRank[quality] or 0) > (qualRank[entry.bestQuality] or 0) then
        entry.bestQuality = quality
    end
end

--- 图鉴收录数
function GameState.getBestiaryCount()
    local count = 0
    for _, entry in pairs(GameState.data.bestiary) do
        if entry.captured then count = count + 1 end
    end
    return count
end

--- 图鉴发现数
function GameState.getDiscoveredCount()
    local count = 0
    for _, entry in pairs(GameState.data.bestiary) do
        if entry.discovered then count = count + 1 end
    end
    return count
end

--- 结算：将本局收益合入全局
function GameState.settleSession(sessionContracts, sessionResources, lostContracts)
    -- 合入资源
    for resType, amount in pairs(sessionResources or {}) do
        GameState.addResource(resType, amount)
    end

    -- 合入成功灵契
    for _, contract in ipairs(sessionContracts or {}) do
        GameState.recordBeast(contract.beastId, contract.quality)
        GameState.data.totalCaptures = GameState.data.totalCaptures + 1
    end

    GameState.data.totalExplorations = GameState.data.totalExplorations + 1
    GameState.data.totalEvacuations = GameState.data.totalEvacuations + 1

    GameState.save()
end

--- 每日签到检查
function GameState.checkDailyLogin()
    local today = os.date and os.date("%Y-%m-%d") or "2026-01-01"
    if GameState.data.lastLoginDate ~= today then
        GameState.data.lastLoginDate = today
        GameState.data.loginDays = GameState.data.loginDays + 1
        return true -- 是新的一天
    end
    return false
end

--- 重置存档（调试用）
function GameState.resetAll()
    GameState.data = deepCopy(DEFAULT_DATA)
    GameState.save()
end

return GameState
