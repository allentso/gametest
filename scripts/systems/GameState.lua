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
    lingyin = 0,       -- 灵印（荣耀货币）

    -- 封灵器库存
    sealer_t2 = 0,     -- 青玉壶
    sealer_t3 = 0,     -- 金缕珠
    sealer_t4 = 0,     -- 天命盘
    sealer_t5 = 0,     -- 混沌印

    -- 道具库存
    rushWard = 0,      -- 疾风符
    fogMap = 0,        -- 迷雾残图
    sealEcho = 0,      -- 封印回响

    -- 图鉴
    bestiary = {},

    -- 统计
    totalExplorations = 0,
    totalCaptures = 0,
    totalEvacuations = 0,

    -- 封灵师境界
    sealerLevel = 1,   -- 当前境界 (1-7)
    sealerExp = 0,     -- 当前经验值
    schoolProgress = {},-- 流派进度 { [schoolId] = level }

    -- 玩家生命值（跨局持久化，不自动恢复）
    hp = 10,

    -- 每日
    loginDays = 0,
    lastLoginDate = "",
    dailyClaimed = {},

    -- 技能解锁统计
    moyaRetreatCount = 0,  -- 被墨鸦攻击后成功撤退次数

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

--- 境界经验阈值
local LEVEL_THRESHOLDS = { 0, 500, 1500, 3000, 6000, 12000, 25000 }

--- 添加封灵师经验
function GameState.addExp(amount)
    GameState.data.sealerExp = (GameState.data.sealerExp or 0) + amount
    -- 检查升级
    local level = GameState.data.sealerLevel or 1
    while level < 7 do
        local needed = LEVEL_THRESHOLDS[level + 1]
        if needed and GameState.data.sealerExp >= needed then
            level = level + 1
            GameState.data.sealerLevel = level
        else
            break
        end
    end
end

--- 获取当前境界
function GameState.getSealerLevel()
    return GameState.data.sealerLevel or 1
end

--- 获取经验进度 (当前/下一级所需)
function GameState.getExpProgress()
    local level = GameState.data.sealerLevel or 1
    local exp = GameState.data.sealerExp or 0
    local current = LEVEL_THRESHOLDS[level] or 0
    local next = LEVEL_THRESHOLDS[level + 1] or current
    return exp - current, next - current
end

--- 结算：将本局收益合入全局
--- @param sessionContracts table 成功灵契列表
--- @param sessionResources table 资源收益
--- @param lostContracts table 丢失灵契列表
--- @param options table|nil { evacType = "normal"|"forced"|"timeout" }
function GameState.settleSession(sessionContracts, sessionResources, lostContracts, options)
    options = options or {}
    local evacType = options.evacType or "normal"

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

    -- 结算封灵师经验（按撤离类型区分）
    local exp = 50  -- 完成一局基础经验
    if evacType == "normal" then
        -- 正常撤离：+80经验，计入撤离统计
        exp = exp + 80
        GameState.data.totalEvacuations = GameState.data.totalEvacuations + 1
    elseif evacType == "forced" then
        -- 强制撤离(forceEnd)：经验减半，不计入撤离统计
        exp = math.floor(exp * 0.5)
    end
    -- timeout: 超时被吞噬，无额外经验

    for _, contract in ipairs(sessionContracts or {}) do
        local qExp = ({ R = 20, SR = 60, SSR = 200 })[contract.quality] or 20
        exp = exp + qExp
        -- 首次收录新异兽
        local entry = GameState.data.bestiary[contract.beastId]
        if entry and entry.count == 1 then
            exp = exp + 100
        end
    end
    GameState.addExp(exp)

    -- 流派进度+1（仅正常撤离）
    if evacType == "normal" then
        local SessionStateRef = require("systems.SessionState")
        local school = SessionStateRef.selectedSchool
        if school then
            GameState.data.schoolProgress[school] = (GameState.data.schoolProgress[school] or 0) + 1
        end
    end

    GameState.save()
end

--- 每日签到检查
function GameState.checkDailyLogin()
    local today = os.date and os.date("%Y-%m-%d") or "2026-01-01"
    if GameState.data.lastLoginDate ~= today then
        GameState.data.lastLoginDate = today
        GameState.data.loginDays = GameState.data.loginDays + 1
        -- 重置每日任务领取状态和进度
        GameState.data.dailyClaimed = {}
        local DailySystem = require("systems.DailySystem")
        DailySystem.reset()
        GameState.save()
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
