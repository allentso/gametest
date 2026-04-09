--- 追踪系统 - 3线索→SR / 5线索+玄采判定→SSR
local EventBus = require("systems.EventBus")
local PitySystem = require("systems.PitySystem")

local TrackingSystem = {}

TrackingSystem.CLUE_TYPES = {
    footprint  = { investigate_time = 2.0, info = "direction" },
    resonance  = { investigate_time = 2.0, info = "quality" },
    nest       = { investigate_time = 2.0, info = "species" },
    scentMark  = { investigate_time = 2.0, info = "resources" },
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
    TrackingSystem.extraXuancaiBonus = 0
    TrackingSystem.ssrReduceBonus = 0
    TrackingSystem.schoolXuancaiBonus = 0
    TrackingSystem.investigatedTypes = {}
    TrackingSystem.habitDeduced = false
end

function TrackingSystem.getInvestigateTime(clueType, hasTraceAsh)
    if hasTraceAsh then return TrackingSystem.FAST_INVESTIGATE_TIME end
    local ct = TrackingSystem.CLUE_TYPES[clueType]
    return ct and ct.investigate_time or 2.0
end

function TrackingSystem.investigate(clue, consumeTraceAsh)
    TrackingSystem.clueCount = TrackingSystem.clueCount + 1
    clue.investigated = true
    if consumeTraceAsh then
        local SessionState = require("systems.SessionState")
        SessionState.addItem("traceAsh", -1)
    end

    -- 记录已调查的线索类型
    TrackingSystem.investigatedTypes[clue.type] = true
    -- 检查习性推断（3种不同类型线索）
    local typeCount = 0
    for _ in pairs(TrackingSystem.investigatedTypes) do typeCount = typeCount + 1 end
    if typeCount >= 3 and not TrackingSystem.habitDeduced then
        TrackingSystem.habitDeduced = true
        EventBus.emit("habit_deduced")
    end

    EventBus.emit("clue_collected", clue.type, TrackingSystem.clueCount)

    -- 3线索 → SR
    if TrackingSystem.clueCount >= 3 and not TrackingSystem.srTriggered then
        TrackingSystem.srTriggered = true
        EventBus.emit("beast_spawn_request", "SR")
    end

    -- 5线索 → 玄采判定（追迹大成可减少所需线索数）
    local ssrThreshold = 5 - (TrackingSystem.ssrReduceBonus or 0)
    if TrackingSystem.clueCount >= ssrThreshold and not TrackingSystem.ssrTriggered then
        TrackingSystem.ssrTriggered = true
        if TrackingSystem.rollXuancai(false, false) then
            EventBus.emit("beast_spawn_request", "SSR")
        else
            EventBus.emit("beast_spawn_request", "SR")
        end
    end

    -- 8+线索 → 额外SSR概率（每多1条+3%本局累积）
    if TrackingSystem.clueCount > 8 then
        TrackingSystem.extraXuancaiBonus = (TrackingSystem.clueCount - 8) * 0.03
    end
end

--- 玄采判定: 基础15% + 线索加成 + 封灵器加成 + 保底加成 + 流派加成
function TrackingSystem.rollXuancai(hasT4, hasT5)
    local base = 0.15
    local extraClues = math.max(0, TrackingSystem.clueCount - 5)
    local clueBonus = extraClues * 0.05
    local sealerBonus = 0
    if hasT5 then sealerBonus = 0.20
    elseif hasT4 then sealerBonus = 0.10
    end
    local pityBonus = PitySystem.getSSRXuancaiBonus()
    local extraBonus = TrackingSystem.extraXuancaiBonus or 0
    -- 追迹流大成：玄采概率+10%
    local schoolBonus = TrackingSystem.schoolXuancaiBonus or 0
    local totalChance = base + clueBonus + sealerBonus + pityBonus + extraBonus + schoolBonus
    return math.random() < totalChance
end

return TrackingSystem
