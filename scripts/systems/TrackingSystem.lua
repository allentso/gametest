--- 追踪系统 - 3线索→SR / 5线索+闪光判定→SSR
local EventBus = require("systems.EventBus")
local PitySystem = require("systems.PitySystem")

local TrackingSystem = {}

TrackingSystem.CLUE_TYPES = {
    footprint  = { investigate_time = 2.0 },
    resonance  = { investigate_time = 2.0 },
    nest       = { investigate_time = 2.0 },
}
TrackingSystem.FAST_INVESTIGATE_TIME = 0.5

TrackingSystem.clueCount = 0
TrackingSystem.clues = {}
TrackingSystem.srTriggered = false
TrackingSystem.ssrTriggered = false

function TrackingSystem.reset()
    TrackingSystem.clueCount = 0
    TrackingSystem.clues = {}
    TrackingSystem.srTriggered = false
    TrackingSystem.ssrTriggered = false
end

function TrackingSystem.getInvestigateTime(clueType, hasTraceAsh)
    if hasTraceAsh then return TrackingSystem.FAST_INVESTIGATE_TIME end
    local ct = TrackingSystem.CLUE_TYPES[clueType]
    return ct and ct.investigate_time or 2.0
end

function TrackingSystem.investigate(clue, hasTraceAsh)
    TrackingSystem.clueCount = TrackingSystem.clueCount + 1
    clue.investigated = true
    if hasTraceAsh then
        EventBus.emit("resource_changed", "traceAsh", -1)
    end
    EventBus.emit("clue_collected", clue.type, TrackingSystem.clueCount)

    -- 3线索 → SR
    if TrackingSystem.clueCount >= 3 and not TrackingSystem.srTriggered then
        TrackingSystem.srTriggered = true
        EventBus.emit("beast_spawn_request", "SR")
    end

    -- 5线索 → 闪光判定
    if TrackingSystem.clueCount >= 5 and not TrackingSystem.ssrTriggered then
        TrackingSystem.ssrTriggered = true
        if TrackingSystem.rollFlash(false) then
            EventBus.emit("beast_spawn_request", "SSR")
        else
            EventBus.emit("beast_spawn_request", "SR")
        end
    end
end

--- 闪光判定: 基础15% + 每多1线索(超5)+5% + 天命盘+15% + 保底加成
function TrackingSystem.rollFlash(hasTianmingpan)
    local base = 0.15
    local extraClues = math.max(0, TrackingSystem.clueCount - 5)
    local clueBonus = extraClues * 0.05
    local sealerBonus = hasTianmingpan and 0.15 or 0
    local pityBonus = PitySystem.getSSRFlashBonus()
    local totalChance = base + clueBonus + sealerBonus + pityBonus
    return math.random() < totalChance
end

return TrackingSystem
