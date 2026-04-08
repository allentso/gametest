--- 灾变计时器 - 4阶段自动递进
local EventBus = require("systems.EventBus")

local Timer = {}

Timer.duration = 480     -- 8 分钟
Timer.elapsed = 0
Timer.phase = "calm"

local PHASES = {
    { name = "calm",     start = 0,   endt = 180 },
    { name = "warning",  start = 180, endt = 300 },
    { name = "danger",   start = 300, endt = 420 },
    { name = "collapse", start = 420, endt = 480 },
}

local PHASE_NAMES = {
    calm     = "灵气平和",
    warning  = "灵气紊乱",
    danger   = "瘴气弥漫",
    collapse = "天崩地裂",
    collapsed = "时尽",
}

function Timer.reset(duration)
    Timer.duration = duration or 480
    Timer.elapsed = 0
    Timer.phase = "calm"
end

function Timer.update(dt)
    Timer.elapsed = Timer.elapsed + dt
    local newPhase = "calm"
    for _, p in ipairs(PHASES) do
        if Timer.elapsed >= p.start and Timer.elapsed < p.endt then
            newPhase = p.name
            break
        end
    end
    if Timer.elapsed >= Timer.duration then
        newPhase = "collapsed"
    end
    if newPhase ~= Timer.phase then
        Timer.phase = newPhase
        EventBus.emit("phase_changed", Timer.phase, Timer.getRemaining())
    end
end

function Timer.getRemaining()
    return math.max(0, Timer.duration - Timer.elapsed)
end

function Timer.getPhase()
    return Timer.phase
end

function Timer.getPhaseName()
    return PHASE_NAMES[Timer.phase] or ""
end

--- 获取灾变吞噬进度 (0~1)
function Timer.getCollapseProgress()
    if Timer.phase == "calm" then return 0 end
    if Timer.phase == "warning" then
        return (Timer.elapsed - 180) / (300 - 180) * 0.3
    end
    if Timer.phase == "danger" then
        return 0.3 + (Timer.elapsed - 300) / (420 - 300) * 0.4
    end
    if Timer.phase == "collapse" or Timer.phase == "collapsed" then
        return 0.7 + math.min(0.3, (Timer.elapsed - 420) / (480 - 420) * 0.3)
    end
    return 0
end

--- 获取超时秒数（用于分层惩罚）
function Timer.getOvertimeSeconds()
    return math.max(0, Timer.elapsed - Timer.duration)
end

--- 格式化剩余时间
function Timer.formatRemaining()
    local sec = math.ceil(Timer.getRemaining())
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%02d : %02d", m, s)
end

return Timer
