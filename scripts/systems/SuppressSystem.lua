--- 压制系统 QTE - 10种异兽独立模式
--- v3.0 QTE 模式映射（Phase 1 暂用已有模式）
--- timing/fire/dual/lightning/glow/strong/tidal/soundwave/charge/rhythm/flip
local EventBus = require("systems.EventBus")

local SuppressSystem = {}

SuppressSystem.MODE_TIMING    = "timing"
SuppressSystem.MODE_FIRE      = "fire"
SuppressSystem.MODE_DUAL      = "dual"
SuppressSystem.MODE_LIGHTNING  = "lightning"
SuppressSystem.MODE_GLOW      = "glow"
SuppressSystem.MODE_STRONG    = "strong"
SuppressSystem.MODE_TIDAL     = "tidal"
SuppressSystem.MODE_SOUNDWAVE = "soundwave"
SuppressSystem.MODE_CHARGE    = "charge"
SuppressSystem.MODE_RHYTHM    = "rhythm"
SuppressSystem.MODE_FLIP      = "flip"
SuppressSystem.MODE_RAPID     = "rhythm"

local BEAST_QTE_MAP = {
    -- SSR · 六灵
    ["001"] = "dual",       -- 烛龙：昼夜交替 → Phase 1 暂用 dual
    ["002"] = "lightning",  -- 应龙：龙翼压制 → Phase 1 暂用 lightning
    ["003"] = "rhythm",     -- 凤凰：五音节律 → Phase 1 暂用 rhythm
    ["004"] = "glow",       -- 白泽：万象感应 → Phase 1 暂用 glow
    ["005"] = "strong",     -- 白虎：金爪压制 → Phase 1 暂用 strong
    ["006"] = "glow",       -- 麒麟：四灵共鸣 → Phase 1 暂用 glow
    -- SR · 十异
    ["007"] = "strong",     -- 饕餮：吞噬抵抗 → Phase 1 暂用 strong
    ["008"] = "charge",     -- 穷奇：刺甲穿透 → Phase 1 暂用 charge
    ["009"] = "strong",     -- 梼杌：顽石破碎 → Phase 1 暂用 strong
    ["010"] = "rhythm",     -- 混沌：无面歌舞 → Phase 1 暂用 rhythm
    ["011"] = "fire",       -- 九婴：九首轮番 → Phase 1 暂用 fire
    ["012"] = "tidal",      -- 猰貐：蛇身压制 → Phase 1 暂用 tidal
    ["013"] = "rhythm",     -- 毕方：单足节律 → Phase 1 暂用 rhythm
    ["014"] = "flip",       -- 乘黄：驰骋 → Phase 1 暂用 flip
    ["015"] = "flip",       -- 文鳐鱼：振翅飞越 → Phase 1 暂用 flip
    ["016"] = "soundwave",  -- 九尾狐：幻化变身 → Phase 1 暂用 soundwave
    -- R · 八兆
    ["017"] = "timing",     -- 帝江：标准计时
    ["018"] = "timing",     -- 当康：标准计时
    ["019"] = "timing",     -- 狸力：标准计时
    ["020"] = "charge",     -- 旋龟：蓄力点击
    ["021"] = "dual",       -- 并封：双端计时
    ["022"] = "timing",     -- 何罗鱼：连点
    ["023"] = "soundwave",  -- 化蛇：声波捕捉
    ["024"] = "charge",     -- 蜚：蓄力点击
}

SuppressSystem.state = {
    mode = "timing",
    beastId = nil,
    quality = "R",
    active = false,
    elapsed = 0,

    pointer = 0, direction = 1, speed = 1.0,
    targetZone = { 0.30, 0.70 },
    hitCount = 0, requiredHits = 1,

    fireActive = false, fireTimer = 0,
    fireOrigZone = nil, fireCooldown = 0,

    pointer2 = 0, direction2 = 1, speed2 = 1.0,
    targetZone2 = { 0.35, 0.65 },
    dualHit1 = false, dualHit2 = false,
    dualSyncTimer = 0, dualSyncWindow = 1.0,

    shakeOffset = 0, shakeCooldown = 0,

    glowCenter = 0.5, glowRadius = 0.12, baseSpeed = 1.0,

    stunTimer = 0, stunDuration = 0.5,

    tidalPhase = 0, tidalPeriod = 2.0,
    tidalBaseZone = { 0.35, 0.65 }, tidalAmplitude = 0.12,

    ringRadius = 1.0, ringTargetRadius = 0.25,
    ringHitTolerance = 0.08, ringSpeed = 0.4,
    ringHits = 0, ringRequired = 2, ringPause = 0,

    chargeProgress = 0, chargeZone = { 0.55, 0.80 },
    charging = false, chargeSpeed = 0.667,

    tapCount = 0, requiredTaps = 8,
    rapidTimer = 0, rapidDuration = 3.0,
    lastTapTime = -1, maxInterval = 0.5,

    flipped = false, flipWarning = false,
    flipWarningTimer = 0, flipCooldown = 0,
}

------------------------------------------------------------
-- Start
------------------------------------------------------------
function SuppressSystem.start(beast, hasMirrorSand)
    local s = SuppressSystem.state
    local id = beast.id or beast.type or "001"
    local quality = beast.quality or "R"
    local isSSR = quality == "SSR"
    local isSR  = quality == "SR"

    s.active   = true
    s.elapsed  = 0
    s.beastId  = id
    s.quality  = quality
    s.hitCount = 0
    s.pointer  = 0
    s.direction = 1

    s.mode = BEAST_QTE_MAP[id] or "timing"

    if isSSR then
        s.speed = 2.0; s.requiredHits = 2; s.targetZone = { 0.38, 0.62 }
    elseif isSR then
        s.speed = 1.6; s.requiredHits = 2; s.targetZone = { 0.35, 0.65 }
    else
        s.speed = 1.0; s.requiredHits = 1; s.targetZone = { 0.30, 0.70 }
    end

    -- Mode-specific init
    local m = s.mode
    if m == "fire" then
        s.fireActive = false; s.fireTimer = 0; s.fireOrigZone = nil
        s.fireCooldown = 2.0 + math.random() * 1.0

    elseif m == "dual" then
        s.pointer2 = 0; s.direction2 = -1
        s.speed2 = s.speed * 0.9
        s.targetZone2 = { s.targetZone[1] + 0.02, s.targetZone[2] - 0.02 }
        s.dualHit1 = false; s.dualHit2 = false; s.dualSyncTimer = 0
        s.dualSyncWindow = isSSR and 0.7 or 1.0
        s.requiredHits = 1

    elseif m == "lightning" then
        s.shakeOffset = 0
        s.shakeCooldown = 0.8 + math.random() * 0.5

    elseif m == "glow" then
        s.glowCenter = 0.5
        s.glowRadius = isSSR and 0.08 or 0.12
        s.baseSpeed = s.speed

    elseif m == "strong" then
        s.requiredHits = 3
        s.targetZone = isSSR and { 0.15, 0.75 } or { 0.20, 0.80 }
        s.stunTimer = 0; s.stunDuration = 0.5
        s.speed = isSSR and 1.8 or (isSR and 1.4 or 1.0)

    elseif m == "tidal" then
        s.tidalPhase = 0
        s.tidalPeriod = isSSR and 1.5 or 2.0
        s.tidalBaseZone = { s.targetZone[1], s.targetZone[2] }
        s.tidalAmplitude = isSSR and 0.15 or 0.12
        s.requiredHits = isSSR and 2 or 1

    elseif m == "soundwave" then
        s.ringRadius = 1.0
        s.ringTargetRadius = 0.25
        s.ringHitTolerance = isSSR and 0.06 or 0.08
        s.ringSpeed = isSSR and 0.5 or 0.4
        s.ringHits = 0; s.ringRequired = 2; s.ringPause = 0

    elseif m == "charge" then
        s.chargeProgress = 0; s.charging = false
        s.chargeSpeed = 1.0 / (isSSR and 1.2 or 1.5)
        s.chargeZone = isSSR and { 0.60, 0.78 } or { 0.55, 0.80 }
        s.requiredHits = 1

    elseif m == "rhythm" then
        s.tapCount = 0; s.lastTapTime = -1
        s.requiredTaps = isSSR and 10 or 8
        s.rapidTimer = 0
        s.rapidDuration = isSSR and 3.5 or 3.0
        s.maxInterval = isSSR and 0.4 or 0.5

    elseif m == "flip" then
        s.flipped = false; s.flipWarning = false; s.flipWarningTimer = 0
        s.flipCooldown = 1.5 + math.random() * 1.0
    end

    if hasMirrorSand then SuppressSystem.applyMirrorSand() end
    if beast.ambushBonus then SuppressSystem.applyAmbush() end
    if beast.burstWindow then SuppressSystem.applyBurstWindow() end
end

------------------------------------------------------------
-- Bonuses
------------------------------------------------------------
local function isTimingFamily(m)
    return m == "timing" or m == "fire" or m == "lightning" or m == "glow"
        or m == "strong" or m == "tidal" or m == "flip"
end

function SuppressSystem.applyMirrorSand()
    local s = SuppressSystem.state
    if isTimingFamily(s.mode) then
        s.targetZone[1] = s.targetZone[1] - 0.05
        s.targetZone[2] = s.targetZone[2] + 0.05
    elseif s.mode == "dual" then
        s.targetZone[1]  = s.targetZone[1]  - 0.05
        s.targetZone[2]  = s.targetZone[2]  + 0.05
        s.targetZone2[1] = s.targetZone2[1] - 0.05
        s.targetZone2[2] = s.targetZone2[2] + 0.05
    elseif s.mode == "rhythm" then
        s.requiredTaps = math.max(4, s.requiredTaps - 2)
    elseif s.mode == "soundwave" then
        s.ringHitTolerance = s.ringHitTolerance + 0.03
    elseif s.mode == "charge" then
        s.chargeZone[1] = s.chargeZone[1] - 0.05
        s.chargeZone[2] = math.min(0.95, s.chargeZone[2] + 0.05)
    end
end

function SuppressSystem.applyAmbush()
    local s = SuppressSystem.state
    if isTimingFamily(s.mode) or s.mode == "dual" then
        local function expandZone(zone)
            local w = zone[2] - zone[1]
            local e = w * 0.15 * 0.5
            zone[1] = math.max(0.05, zone[1] - e)
            zone[2] = math.min(0.95, zone[2] + e)
        end
        expandZone(s.targetZone)
        if s.mode == "dual" then expandZone(s.targetZone2) end
    elseif s.mode == "rhythm" then
        s.requiredTaps = math.max(4, s.requiredTaps - 2)
        s.rapidDuration = s.rapidDuration + 0.5
    elseif s.mode == "soundwave" then
        s.ringHitTolerance = s.ringHitTolerance + 0.04
    elseif s.mode == "charge" then
        s.chargeZone[1] = math.max(0.10, s.chargeZone[1] - 0.05)
        s.chargeZone[2] = math.min(0.95, s.chargeZone[2] + 0.05)
    end
end

function SuppressSystem.applyBurstWindow()
    local s = SuppressSystem.state
    if isTimingFamily(s.mode) or s.mode == "dual" then
        local w = s.targetZone[2] - s.targetZone[1]
        local e = w * 0.20 * 0.5
        s.targetZone[1] = math.max(0.05, s.targetZone[1] - e)
        s.targetZone[2] = math.min(0.95, s.targetZone[2] + e)
    end
end

------------------------------------------------------------
-- Update dispatch
------------------------------------------------------------
function SuppressSystem.update(dt)
    local s = SuppressSystem.state
    if not s.active then return end
    s.elapsed = s.elapsed + dt

    local fn = SuppressSystem["update_" .. s.mode]
    if fn then fn(dt) end
end

local function movePointer(s, dt, spd)
    spd = spd or s.speed
    s.pointer = s.pointer + s.direction * spd * dt
    if s.pointer >= 1.0 then s.pointer = 1.0; s.direction = -1 end
    if s.pointer <= 0.0 then s.pointer = 0.0; s.direction =  1 end
end

function SuppressSystem.update_timing(dt) movePointer(SuppressSystem.state, dt) end

function SuppressSystem.update_fire(dt)
    local s = SuppressSystem.state
    movePointer(s, dt)
    if s.fireActive then
        s.fireTimer = s.fireTimer - dt
        if s.fireTimer <= 0 then
            s.fireActive = false
            s.targetZone = { s.fireOrigZone[1], s.fireOrigZone[2] }
            s.fireOrigZone = nil
            s.fireCooldown = 1.5 + math.random() * 1.5
        end
    else
        s.fireCooldown = s.fireCooldown - dt
        if s.fireCooldown <= 0 then
            s.fireActive = true; s.fireTimer = 0.5
            s.fireOrigZone = { s.targetZone[1], s.targetZone[2] }
            local w = s.targetZone[2] - s.targetZone[1]
            local c = 0.2 + math.random() * 0.6
            s.targetZone = { c - w * 0.5, c + w * 0.5 }
        end
    end
end

function SuppressSystem.update_dual(dt)
    local s = SuppressSystem.state
    movePointer(s, dt)
    s.pointer2 = s.pointer2 + s.direction2 * s.speed2 * dt
    if s.pointer2 >= 1.0 then s.pointer2 = 1.0; s.direction2 = -1 end
    if s.pointer2 <= 0.0 then s.pointer2 = 0.0; s.direction2 =  1 end
    if s.dualHit1 or s.dualHit2 then
        s.dualSyncTimer = s.dualSyncTimer + dt
        if s.dualSyncTimer > s.dualSyncWindow then
            s.dualHit1 = false; s.dualHit2 = false; s.dualSyncTimer = 0
        end
    end
end

function SuppressSystem.update_lightning(dt)
    local s = SuppressSystem.state
    movePointer(s, dt)
    s.shakeCooldown = s.shakeCooldown - dt
    if s.shakeCooldown <= 0 then
        s.shakeOffset = (math.random() - 0.5) * 0.15
        s.shakeCooldown = 0.3 + math.random() * 0.4
    end
end

function SuppressSystem.update_glow(dt)
    local s = SuppressSystem.state
    local dist = math.abs(s.pointer - s.glowCenter)
    local mult = dist < s.glowRadius and 0.4 or 1.0
    movePointer(s, dt, s.baseSpeed * mult)
end

function SuppressSystem.update_strong(dt)
    local s = SuppressSystem.state
    if s.stunTimer > 0 then
        s.stunTimer = s.stunTimer - dt
        return
    end
    movePointer(s, dt)
end

function SuppressSystem.update_tidal(dt)
    local s = SuppressSystem.state
    movePointer(s, dt)
    s.tidalPhase = s.tidalPhase + dt
    local wave = math.sin(s.tidalPhase * math.pi * 2 / s.tidalPeriod) * s.tidalAmplitude
    s.targetZone[1] = s.tidalBaseZone[1] - wave
    s.targetZone[2] = s.tidalBaseZone[2] + wave
end

function SuppressSystem.update_soundwave(dt)
    local s = SuppressSystem.state
    if s.ringPause > 0 then
        s.ringPause = s.ringPause - dt
        if s.ringPause <= 0 then s.ringRadius = 1.0 end
        return
    end
    s.ringRadius = s.ringRadius - s.ringSpeed * dt
    if s.ringRadius <= 0 then s.active = false end
end

function SuppressSystem.update_charge(dt)
    local s = SuppressSystem.state
    if s.charging then
        s.chargeProgress = s.chargeProgress + s.chargeSpeed * dt
        if s.chargeProgress >= 1.0 then
            s.chargeProgress = 0; s.charging = false
        end
    end
end

function SuppressSystem.update_rhythm(dt)
    local s = SuppressSystem.state
    s.rapidTimer = s.rapidTimer + dt
    if s.rapidTimer >= s.rapidDuration then s.active = false; return end
    if s.lastTapTime >= 0 and s.tapCount > 0 then
        if (s.rapidTimer - s.lastTapTime) > s.maxInterval then
            s.tapCount = 0; s.lastTapTime = -1
        end
    end
end

function SuppressSystem.update_flip(dt)
    local s = SuppressSystem.state
    movePointer(s, dt)
    if s.flipWarning then
        s.flipWarningTimer = s.flipWarningTimer - dt
        if s.flipWarningTimer <= 0 then
            s.flipped = not s.flipped
            s.flipWarning = false
            s.flipCooldown = 1.2 + math.random() * 1.5
        end
    else
        s.flipCooldown = s.flipCooldown - dt
        if s.flipCooldown <= 0 then
            s.flipWarning = true; s.flipWarningTimer = 0.3
        end
    end
end

------------------------------------------------------------
-- Tap dispatch
------------------------------------------------------------
function SuppressSystem.tap(barIndex)
    local s = SuppressSystem.state
    if not s.active then return nil end
    local fn = SuppressSystem["tap_" .. s.mode]
    if fn then return fn(barIndex) end
    return nil
end

local function hitOrFinish(s)
    s.hitCount = s.hitCount + 1
    if s.hitCount >= s.requiredHits then s.active = false; return "success" end
    s.speed = s.speed * 1.15
    s.targetZone[1] = s.targetZone[1] + 0.02
    s.targetZone[2] = s.targetZone[2] - 0.02
    return "hit"
end

function SuppressSystem.tap_timing()
    local s = SuppressSystem.state
    if s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2] then
        return hitOrFinish(s)
    end
    s.active = false; return "fail"
end

function SuppressSystem.tap_fire()
    return SuppressSystem.tap_timing()
end

function SuppressSystem.tap_dual(barIndex)
    local s = SuppressSystem.state
    barIndex = barIndex or 1
    if barIndex == 1 then
        if s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2] then
            if not s.dualHit1 then
                s.dualHit1 = true
                if not s.dualHit2 then s.dualSyncTimer = 0 end
            end
        else
            s.active = false; return "fail"
        end
    else
        if s.pointer2 >= s.targetZone2[1] and s.pointer2 <= s.targetZone2[2] then
            if not s.dualHit2 then
                s.dualHit2 = true
                if not s.dualHit1 then s.dualSyncTimer = 0 end
            end
        else
            s.active = false; return "fail"
        end
    end
    if s.dualHit1 and s.dualHit2 then
        s.hitCount = s.hitCount + 1
        if s.hitCount >= s.requiredHits then s.active = false; return "success" end
        s.dualHit1 = false; s.dualHit2 = false; s.dualSyncTimer = 0
        return "hit"
    end
    return "hit"
end

function SuppressSystem.tap_lightning()
    local s = SuppressSystem.state
    local ep = math.max(0, math.min(1, s.pointer + s.shakeOffset))
    if ep >= s.targetZone[1] and ep <= s.targetZone[2] then
        return hitOrFinish(s)
    end
    s.active = false; return "fail"
end

function SuppressSystem.tap_glow()
    return SuppressSystem.tap_timing()
end

function SuppressSystem.tap_strong()
    local s = SuppressSystem.state
    if s.stunTimer > 0 then return nil end
    if s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2] then
        s.hitCount = s.hitCount + 1
        if s.hitCount >= s.requiredHits then s.active = false; return "success" end
        s.stunTimer = s.stunDuration
        s.speed = s.speed * 1.2
        return "hit"
    end
    s.active = false; return "fail"
end

function SuppressSystem.tap_tidal()
    return SuppressSystem.tap_timing()
end

function SuppressSystem.tap_soundwave()
    local s = SuppressSystem.state
    if s.ringPause > 0 then return nil end
    if math.abs(s.ringRadius - s.ringTargetRadius) <= s.ringHitTolerance then
        s.ringHits = s.ringHits + 1
        if s.ringHits >= s.ringRequired then s.active = false; return "success" end
        s.ringPause = 0.5; s.ringSpeed = s.ringSpeed * 1.2
        return "hit"
    end
    s.active = false; return "fail"
end

function SuppressSystem.tap_rhythm()
    local s = SuppressSystem.state
    s.tapCount = s.tapCount + 1
    s.lastTapTime = s.rapidTimer
    if s.tapCount >= s.requiredTaps then s.active = false; return "success" end
    return "hit"
end

function SuppressSystem.tap_flip()
    local s = SuppressSystem.state
    local inZone = s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2]
    if s.flipped then inZone = not inZone end
    if inZone then return hitOrFinish(s) end
    s.active = false; return "fail"
end

------------------------------------------------------------
-- Charge: start / release
------------------------------------------------------------
function SuppressSystem.chargeStart()
    local s = SuppressSystem.state
    if not s.active or s.mode ~= "charge" then return nil end
    s.charging = true
end

function SuppressSystem.chargeRelease()
    local s = SuppressSystem.state
    if not s.active or s.mode ~= "charge" then return nil end
    s.charging = false
    if s.chargeProgress >= s.chargeZone[1] and s.chargeProgress <= s.chargeZone[2] then
        s.hitCount = s.hitCount + 1
        if s.hitCount >= s.requiredHits then s.active = false; return "success" end
        s.chargeProgress = 0; return "hit"
    end
    s.chargeProgress = 0; s.active = false; return "fail"
end

------------------------------------------------------------
-- Getters (backwards compat)
------------------------------------------------------------
function SuppressSystem.getRapidProgress()
    local s = SuppressSystem.state
    if s.mode == "rhythm" then return s.tapCount / s.requiredTaps end
    return 0
end

function SuppressSystem.getRapidTimeRatio()
    local s = SuppressSystem.state
    if s.mode == "rhythm" then return math.max(0, 1 - s.rapidTimer / s.rapidDuration) end
    return 1
end

function SuppressSystem.getMode() return SuppressSystem.state.mode end

return SuppressSystem
