--- SuppressOverlay - 压制 QTE 模态覆盖层
--- 支持10种异兽独立QTE模式渲染与输入
local InkPalette = require("data.InkPalette")
local SuppressSystem = require("systems.SuppressSystem")
local EventBus = require("systems.EventBus")
local ScreenManager = require("systems.ScreenManager")
local BrushStrokes = require("render.BrushStrokes")

local SuppressOverlay = {}
SuppressOverlay.__index = SuppressOverlay

function SuppressOverlay.new(params)
    local self = setmetatable({}, SuppressOverlay)
    self.isModal = true
    self.beast = params.beast
    self.result = nil
    self.resultTimer = 0
    self.RESULT_DURATION = 1.2
    self.hitFlashTimer = 0
    self.shakeTimer = 0
    self.logW = 300
    self.logH = 500
    -- 输入保护：进入时的触摸释放事件不应触发 QTE 判定
    -- 因为 ExploreScreen 在 down 事件中 push 本覆盖层，
    -- 后续的 up/tap 会被传递到这里导致 charge 模式立即释放失败
    self.inputGuard = true
    return self
end

function SuppressOverlay:onEnter() end
function SuppressOverlay:onExit() end

function SuppressOverlay:update(dt)
    if self.result then
        self.resultTimer = self.resultTimer + dt
        if self.resultTimer >= self.RESULT_DURATION then ScreenManager.pop(); return end
        return
    end

    SuppressSystem.update(dt)

    if not SuppressSystem.state.active and not self.result then
        self.result = "fail"; self.resultTimer = 0
        EventBus.emit("suppress_result", "fail")
    end

    if self.hitFlashTimer > 0 then self.hitFlashTimer = self.hitFlashTimer - dt end
    if self.shakeTimer > 0 then self.shakeTimer = self.shakeTimer - dt end
end

------------------------------------------------------------
-- Input
------------------------------------------------------------
function SuppressOverlay:onInput(action, sx, sy)
    if self.result then return true end

    -- 输入保护：吞掉进入时残留的 up/tap，等待第一次全新的 down
    if self.inputGuard then
        if action == "down" then
            self.inputGuard = false  -- 收到全新 down，保护解除
        else
            return true  -- 吞掉残留的 up/tap/move
        end
    end

    local s = SuppressSystem.state

    if s.mode == "charge" then
        if action == "down" then
            SuppressSystem.chargeStart()
        elseif action == "up" or action == "tap" then
            -- tap 事件由 ScreenManager 在 up 之前合成发出，
            -- 若被消费会阻止原始 up 到达，因此 tap 也需触发释放
            self:handleResult(SuppressSystem.chargeRelease())
        end
        return true

    elseif s.mode == "dual" then
        if action == "down" then
            local bar = (sx < self.logW * 0.5) and 1 or 2
            self:handleResult(SuppressSystem.tap(bar))
        end
        return true

    else
        if action == "down" then
            self:handleResult(SuppressSystem.tap())
        end
        return true
    end
end

function SuppressOverlay:handleResult(tapResult)
    if tapResult == "success" then
        self.result = "success"; self.resultTimer = 0
        self.hitFlashTimer = 0.3
        EventBus.emit("suppress_result", "success")
    elseif tapResult == "fail" then
        self.result = "fail"; self.resultTimer = 0
        self.shakeTimer = 0.15
        EventBus.emit("suppress_result", "fail")
    elseif tapResult == "hit" then
        self.hitFlashTimer = 0.3; self.shakeTimer = 0.08
    end
end

------------------------------------------------------------
-- Render
------------------------------------------------------------
local MODE_NAMES = {
    timing = "标准压制", fire = "火焰扰动", dual = "双线同步",
    lightning = "电击抖动", glow = "光晕稳区", strong = "石化三连",
    tidal = "潮汐节律", soundwave = "声波捕捉", charge = "蓄力释放",
    rhythm = "连续节奏", flip = "翻转陷阱",
}

function SuppressOverlay:render(vg, logW, logH, t)
    self.logW = logW; self.logH = logH
    local P = InkPalette
    local s = SuppressSystem.state

    local ox, oy = 0, 0
    if self.shakeTimer > 0 then
        ox = math.sin(t * 40) * 4; oy = math.cos(t * 50) * 3
    end
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)

    nvgBeginPath(vg)
    nvgRect(vg, -10, -10, logW + 20, logH + 20)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.70))
    nvgFill(vg)

    local qc = P.qualColor(self.beast.quality)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(qc.r, qc.g, qc.b, 0.9))
    nvgText(vg, logW * 0.5, logH * 0.22, "【" .. self.beast.quality .. "·" .. self.beast.name .. "】")

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.6))
    nvgText(vg, logW * 0.5, logH * 0.27, MODE_NAMES[s.mode] or "")

    if self.hitFlashTimer > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, logW * 0.5, logH * 0.45, 120)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, (self.hitFlashTimer / 0.3) * 0.30))
        nvgFill(vg)
    end

    if not self.result then
        local fn = self["render_" .. s.mode]
        if fn then fn(self, vg, logW, logH, t) end
    else
        self:renderResult(vg, logW, logH, t)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- Helper: standard timing bar
------------------------------------------------------------
function SuppressOverlay:drawTimingBar(vg, logW, logH, t, opts)
    local P = InkPalette
    local s = SuppressSystem.state
    opts = opts or {}
    local barW = logW * 0.6
    local barH = 18
    local barX = (logW - barW) * 0.5
    local barY = opts.barY or (logH * 0.45)
    local pointer = opts.pointer or s.pointer
    local zone = opts.zone or s.targetZone
    local hits = opts.hits or s.hitCount
    local needed = opts.needed or s.requiredHits
    local color = opts.color or P.jade
    local flipped = opts.flipped

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50))
    nvgFill(vg)

    if flipped then
        local tz1, tz2 = zone[1], zone[2]
        local tzX = barX + tz1 * barW
        local tzW = (tz2 - tz1) * barW
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tzX, barY, tzW, barH, 2)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.35))
        nvgFill(vg)
        if tz1 > 0.05 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX + 2, barY, tz1 * barW - 2, barH, 2)
            nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, 0.30))
            nvgFill(vg)
        end
        if tz2 < 0.95 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX + tz2 * barW, barY, (1 - tz2) * barW - 2, barH, 2)
            nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, 0.30))
            nvgFill(vg)
        end
    else
        local tz1, tz2 = zone[1], zone[2]
        local pa = 0.40 + math.sin(t * 4) * 0.10
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX + tz1 * barW, barY, (tz2 - tz1) * barW, barH, 2)
        nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, pa))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBAf(color.r, color.g, color.b, 0.70))
        nvgStrokeWidth(vg, 1); nvgStroke(vg)
    end

    local px = barX + pointer * barW
    nvgBeginPath(vg)
    nvgMoveTo(vg, px, barY - 2); nvgLineTo(vg, px, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgStrokeWidth(vg, 3); nvgStroke(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px, barY - 4, 5)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85))
    nvgFill(vg)

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
    nvgText(vg, logW * 0.5, barY + barH + 16, "封印 " .. hits .. "/" .. needed)
end

------------------------------------------------------------
-- Mode renderers
------------------------------------------------------------

function SuppressOverlay:render_timing(vg, logW, logH, t)
    self:drawTimingBar(vg, logW, logH, t)
end

function SuppressOverlay:render_fire(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    self:drawTimingBar(vg, logW, logH, t, { color = s.fireActive and P.cinnabar or P.jade })
    if s.fireActive then
        local blink = math.sin(t * 12) > 0 and 0.9 or 0.4
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, blink))
        nvgText(vg, logW * 0.5, logH * 0.38, "!! 火焰扰动 !!")
        for i = 1, 5 do
            local fx = logW * 0.5 + math.sin(t * 3 + i * 1.2) * 40
            local fy = logH * 0.43 + math.cos(t * 4 + i) * 8
            nvgBeginPath(vg)
            nvgCircle(vg, fx, fy, 3 + math.sin(t * 5 + i) * 2)
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g + 0.2, P.cinnabar.b, 0.5))
            nvgFill(vg)
        end
    end
end

function SuppressOverlay:render_dual(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local barW = logW * 0.35
    local barH = 16
    local barY = logH * 0.45

    self:drawDualBar(vg, logW * 0.08, barY, barW, barH, s.pointer, s.targetZone, s.dualHit1, P.jade, t)
    self:drawDualBar(vg, logW * 0.57, barY, barW, barH, s.pointer2, s.targetZone2, s.dualHit2, P.azure, t)

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
    nvgText(vg, logW * 0.08 + barW * 0.5, barY + barH + 8, s.dualHit1 and "OK" or "左半屏")
    nvgText(vg, logW * 0.57 + barW * 0.5, barY + barH + 8, s.dualHit2 and "OK" or "右半屏")

    if s.dualHit1 or s.dualHit2 then
        local ratio = 1 - s.dualSyncTimer / s.dualSyncWindow
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.8))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, logW * 0.5, barY + barH + 28,
            string.format("同步窗口 %.1fs", ratio * s.dualSyncWindow))
    end

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
    nvgText(vg, logW * 0.5, barY + barH + 45, "封印 " .. s.hitCount .. "/" .. s.requiredHits)
end

function SuppressOverlay:drawDualBar(vg, x, y, w, h, pointer, zone, hit, color, t)
    local P = InkPalette
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 3)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50))
    nvgFill(vg)

    local pa = hit and 0.60 or (0.40 + math.sin(t * 4) * 0.10)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + zone[1] * w, y, (zone[2] - zone[1]) * w, h, 2)
    nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, pa))
    nvgFill(vg)
    if hit then
        nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.8))
        nvgStrokeWidth(vg, 2); nvgStroke(vg)
    end

    local px = x + pointer * w
    nvgBeginPath(vg)
    nvgMoveTo(vg, px, y - 2); nvgLineTo(vg, px, y + h + 2)
    nvgStrokeColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgStrokeWidth(vg, 2.5); nvgStroke(vg)
end

function SuppressOverlay:render_lightning(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local ep = math.max(0, math.min(1, s.pointer + s.shakeOffset))
    self:drawTimingBar(vg, logW, logH, t, { pointer = ep, color = P.gold })

    if math.abs(s.shakeOffset) > 0.01 then
        local barW = logW * 0.6
        local barX = (logW - barW) * 0.5
        local px = barX + ep * barW
        for i = 1, 3 do
            nvgBeginPath(vg)
            nvgCircle(vg, px + (math.random() - 0.5) * 20,
                logH * 0.45 + (math.random() - 0.5) * 30, 1.5)
            nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.7))
            nvgFill(vg)
        end
    end
end

function SuppressOverlay:render_glow(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local barW = logW * 0.6
    local barX = (logW - barW) * 0.5
    local barY = logH * 0.45

    self:drawTimingBar(vg, logW, logH, t)

    local gx = barX + s.glowCenter * barW
    local gw = s.glowRadius * barW * 2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gx - gw * 0.5, barY - 2, gw, 22, 4)
    nvgFillColor(vg, nvgRGBAf(1, 1, 0.9, 0.15 + math.sin(t * 2) * 0.05))
    nvgFill(vg)

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBAf(1, 1, 0.8, 0.5))
    nvgText(vg, gx, barY - 4, "光晕减速区")
end

function SuppressOverlay:render_strong(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    self:drawTimingBar(vg, logW, logH, t)
    if s.stunTimer > 0 then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
        nvgText(vg, logW * 0.5, logH * 0.38, "石化硬直...")
    end
end

function SuppressOverlay:render_tidal(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    self:drawTimingBar(vg, logW, logH, t, { color = P.azure })
    local wave = math.sin(s.tidalPhase * math.pi * 2 / s.tidalPeriod)
    local hint = wave > 0.3 and "潮涨" or (wave < -0.3 and "潮落" or "")
    if hint ~= "" then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBAf(P.azure.r, P.azure.g, P.azure.b, 0.6))
        nvgText(vg, logW * 0.5, logH * 0.45 - 4, hint)
    end
end

function SuppressOverlay:render_soundwave(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local cx, cy = logW * 0.5, logH * 0.45
    local maxR = 80

    local tpx = s.ringTargetRadius * maxR
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, tpx)
    nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.6))
    nvgStrokeWidth(vg, 3); nvgStroke(vg)

    local tolPx = s.ringHitTolerance * maxR
    nvgBeginPath(vg); nvgCircle(vg, cx, cy, tpx)
    nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.12))
    nvgStrokeWidth(vg, tolPx * 2); nvgStroke(vg)

    if s.ringPause <= 0 then
        local rpx = s.ringRadius * maxR
        nvgBeginPath(vg); nvgCircle(vg, cx, cy, rpx)
        nvgStrokeColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b,
            0.5 + math.sin(t * 6) * 0.2))
        nvgStrokeWidth(vg, 2.5); nvgStroke(vg)
    end

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
    nvgText(vg, cx, cy + maxR + 20, "声波 " .. s.ringHits .. "/" .. s.ringRequired)
end

function SuppressOverlay:render_charge(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local cx = logW * 0.5
    local gH = logH * 0.35
    local gW = 28
    local gX = cx - gW * 0.5
    local gY = logH * 0.30

    nvgBeginPath(vg)
    nvgRoundedRect(vg, gX, gY, gW, gH, 6)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40))
    nvgFill(vg)

    local z1, z2 = s.chargeZone[1], s.chargeZone[2]
    local zY = gY + gH * (1 - z2)
    local zH = gH * (z2 - z1)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, gX, zY, gW, zH, 2)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.35 + math.sin(t * 3) * 0.1))
    nvgFill(vg)

    local fH = gH * s.chargeProgress
    if fH > 0 then
        local inZone = s.chargeProgress >= z1 and s.chargeProgress <= z2
        local fc = inZone and P.jade or P.cinnabar
        nvgBeginPath(vg)
        nvgRoundedRect(vg, gX + 3, gY + gH - fH, gW - 6, fH, 2)
        nvgFillColor(vg, nvgRGBAf(fc.r, fc.g, fc.b, 0.7))
        nvgFill(vg)
    end

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
    nvgText(vg, cx, gY + gH + 16, s.charging and "松开释放" or "长按蓄力")

    if s.chargeProgress > 0.9 then
        local blink = math.sin(t * 10) > 0 and 0.8 or 0.3
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, blink))
        nvgText(vg, cx, gY - 16, "即将过载!")
    end
end

function SuppressOverlay:render_rhythm(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    local cx, cy = logW * 0.5, logH * 0.45

    nvgBeginPath(vg); nvgCircle(vg, cx, cy, 55)
    nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.30))
    nvgStrokeWidth(vg, 15); nvgStroke(vg)

    local prog = s.tapCount / s.requiredTaps
    if prog > 0 then
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, 55, -math.pi * 0.5,
            -math.pi * 0.5 + math.pi * 2 * prog, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(P.azure.r, P.azure.g, P.azure.b, 0.60))
        nvgStrokeWidth(vg, 15); nvgStroke(vg)
    end

    nvgFontFace(vg, "sans"); nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgText(vg, cx, cy, tostring(s.tapCount))

    if s.lastTapTime >= 0 and s.tapCount > 0 then
        local interval = s.rapidTimer - s.lastTapTime
        local ratio = interval / s.maxInterval
        if ratio > 0.6 then
            nvgBeginPath(vg); nvgCircle(vg, cx, cy, 55)
            nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b,
                math.min(1, (ratio - 0.6) / 0.4) * 0.5))
            nvgStrokeWidth(vg, 3); nvgStroke(vg)
        end
    end

    local tbW = logW * 0.4
    local tbH = 6
    local tbX = (logW - tbW) * 0.5
    local tbY = cy + 80
    local tr = SuppressSystem.getRapidTimeRatio()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, tbX, tbY, tbW, tbH, 3)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.25))
    nvgFill(vg)

    if tr > 0 then
        local lr = P.jade.r + (P.cinnabar.r - P.jade.r) * (1 - tr)
        local lg = P.jade.g + (P.cinnabar.g - P.jade.g) * (1 - tr)
        local lb = P.jade.b + (P.cinnabar.b - P.jade.b) * (1 - tr)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tbX, tbY, tbW * tr, tbH, 3)
        nvgFillColor(vg, nvgRGBAf(lr, lg, lb, 0.7))
        nvgFill(vg)
    end

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.6))
    nvgText(vg, cx, tbY + 10, "保持节奏，不要断链！")
end

function SuppressOverlay:render_flip(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state
    self:drawTimingBar(vg, logW, logH, t, {
        color = s.flipped and P.cinnabar or P.jade,
        flipped = s.flipped,
    })
    if s.flipWarning then
        local blink = math.sin(t * 16) > 0 and 0.9 or 0.3
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, blink))
        nvgText(vg, logW * 0.5, logH * 0.36, "!! 翻转 !!")
    elseif s.flipped then
        nvgFontFace(vg, "sans"); nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.7))
        nvgText(vg, logW * 0.5, logH * 0.38, "已翻转！安全区在外侧")
    end
end

------------------------------------------------------------
-- Result
------------------------------------------------------------
function SuppressOverlay:renderResult(vg, logW, logH, t)
    local P = InkPalette
    local alpha = math.min(1, self.resultTimer / 0.3)
    local text, color
    if self.result == "success" then text = "压制成功"; color = P.jade
    else text = "压制失败"; color = P.cinnabar end

    BrushStrokes.inkWash(vg, logW * 0.5, logH * 0.45, 20, 80, color, alpha * 0.25)
    nvgFontFace(vg, "sans"); nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, alpha * 0.9))
    nvgText(vg, logW * 0.5, logH * 0.45, text)
end

return SuppressOverlay
