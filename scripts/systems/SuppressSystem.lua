--- 压制系统 QTE - 时机点击(R/SR) + 连续封印(SSR)
local EventBus = require("systems.EventBus")

local SuppressSystem = {}

SuppressSystem.MODE_TIMING = "timing"
SuppressSystem.MODE_RAPID  = "rapid"

SuppressSystem.state = {
    mode = "timing",
    pointer = 0, direction = 1, speed = 1.0,
    targetZone = { 0.4, 0.6 },
    hitCount = 0, requiredHits = 1,
    tapCount = 0, requiredTaps = 8,
    rapidTimer = 0, rapidDuration = 3.0,
    active = false,
}

function SuppressSystem.start(beast, hasMirrorSand)
    local s = SuppressSystem.state
    s.hitCount = 0
    s.tapCount = 0
    s.active = true
    s.pointer = 0
    s.direction = 1
    s.rapidTimer = 0

    if beast.quality == "SSR" then
        s.mode = SuppressSystem.MODE_RAPID
        s.requiredTaps = 8
        s.rapidDuration = 3.0
    elseif beast.quality == "SR" then
        s.mode = SuppressSystem.MODE_TIMING
        s.speed = 1.6
        s.requiredHits = 2
        s.targetZone = { 0.35, 0.65 }
    else
        s.mode = SuppressSystem.MODE_TIMING
        s.speed = 1.0
        s.requiredHits = 1
        s.targetZone = { 0.30, 0.70 }
    end

    -- 镇灵砂加成
    if hasMirrorSand then
        if s.mode == SuppressSystem.MODE_TIMING then
            s.targetZone[1] = s.targetZone[1] - 0.05
            s.targetZone[2] = s.targetZone[2] + 0.05
        else
            s.requiredTaps = 6
        end
    end

    -- 偷袭加成
    if beast.ambushBonus then
        if s.mode == SuppressSystem.MODE_TIMING then
            local expand = (s.targetZone[2] - s.targetZone[1]) * 0.30 * 0.5
            s.targetZone[1] = math.max(0.05, s.targetZone[1] - expand)
            s.targetZone[2] = math.min(0.95, s.targetZone[2] + expand)
        else
            s.requiredTaps = math.max(4, s.requiredTaps - 2)
            s.rapidDuration = s.rapidDuration + 0.5
        end
    end
end

function SuppressSystem.update(dt)
    local s = SuppressSystem.state
    if not s.active then return end

    if s.mode == SuppressSystem.MODE_TIMING then
        s.pointer = s.pointer + s.direction * s.speed * dt
        if s.pointer >= 1.0 then s.pointer = 1.0; s.direction = -1 end
        if s.pointer <= 0.0 then s.pointer = 0.0; s.direction = 1 end
    else
        s.rapidTimer = s.rapidTimer + dt
        if s.rapidTimer >= s.rapidDuration then
            s.active = false
            EventBus.emit("suppress_result", "fail")
        end
    end
end

function SuppressSystem.tap()
    local s = SuppressSystem.state
    if not s.active then return nil end

    if s.mode == SuppressSystem.MODE_TIMING then
        if s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2] then
            s.hitCount = s.hitCount + 1
            if s.hitCount >= s.requiredHits then
                s.active = false
                return "success"
            end
            -- 增加难度
            s.speed = s.speed * 1.15
            s.targetZone[1] = s.targetZone[1] + 0.02
            s.targetZone[2] = s.targetZone[2] - 0.02
            return "hit"
        else
            s.active = false
            return "fail"
        end
    else
        s.tapCount = s.tapCount + 1
        if s.tapCount >= s.requiredTaps then
            s.active = false
            return "success"
        end
        return "hit"
    end
end

function SuppressSystem.getRapidProgress()
    local s = SuppressSystem.state
    if s.mode ~= SuppressSystem.MODE_RAPID then return 0 end
    return s.tapCount / s.requiredTaps
end

function SuppressSystem.getRapidTimeRatio()
    local s = SuppressSystem.state
    if s.mode ~= SuppressSystem.MODE_RAPID then return 1 end
    return math.max(0, 1 - s.rapidTimer / s.rapidDuration)
end

return SuppressSystem
