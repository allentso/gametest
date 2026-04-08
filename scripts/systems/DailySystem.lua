--- 每日任务 + 签到奖励
local EventBus = require("systems.EventBus")

local DailySystem = {}
DailySystem._listening = false

DailySystem.tasks = {
    { id = "explore_2",  desc = "成功撤离2次",  target = 2,  reward = { lingshi = 20 } },
    { id = "capture_5",  desc = "捕获5只异兽",  target = 5,  reward = { shouhun = 3 } },
    { id = "capture_sr", desc = "捕获1只异色灵兽", target = 1,  reward = { traceAsh = 5 } },
    { id = "collect_20", desc = "收集20个灵石",  target = 20, reward = { soulCharm = 1 } },
}

DailySystem.progress = {}

function DailySystem.reset()
    DailySystem.progress = {}
    for _, task in ipairs(DailySystem.tasks) do
        DailySystem.progress[task.id] = 0
    end
end

function DailySystem.increment(taskId, amount)
    amount = amount or 1
    DailySystem.progress[taskId] = (DailySystem.progress[taskId] or 0) + amount
end

function DailySystem.isComplete(taskId)
    local task = DailySystem.getTask(taskId)
    return task and (DailySystem.progress[taskId] or 0) >= task.target
end

function DailySystem.allComplete()
    for _, task in ipairs(DailySystem.tasks) do
        if not DailySystem.isComplete(task.id) then return false end
    end
    return true
end

function DailySystem.getTask(id)
    for _, t in ipairs(DailySystem.tasks) do
        if t.id == id then return t end
    end
end

DailySystem.loginRewards = {
    [1] = { lingshi = 15 },
    [2] = { shouhun = 5 },
    [3] = { sealer_t3 = 1 },
    [4] = { lingshi = 20, soulCharm = 2 },
    [5] = { shouhun = 8 },
    [6] = { tianjing = 1 },
    [7] = { sealer_t4 = 1, tianjing = 2 },
}

function DailySystem.getLoginDay(totalDays)
    return ((totalDays - 1) % 7) + 1
end

function DailySystem.listen()
    if DailySystem._listening then return end
    DailySystem._listening = true

    EventBus.on("beast_captured", function(contract, quality)
        DailySystem.increment("capture_5")
        if quality == "SR" or quality == "SSR" then
            DailySystem.increment("capture_sr")
        end
    end, DailySystem)

    EventBus.on("evacuation_result", function(success)
        if success then
            DailySystem.increment("explore_2")
        end
    end, DailySystem)

    EventBus.on("resource_changed", function(resType, amount)
        if resType == "lingshi" and amount and amount > 0 then
            DailySystem.increment("collect_20", amount)
        end
    end, DailySystem)
end

return DailySystem
