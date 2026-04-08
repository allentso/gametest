--- SuppressOverlay - 压制 QTE 模态覆盖层
--- 时机模式(R/SR): 横条指针+目标区
--- 连续模式(SSR): 环形点击+倒计时
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
    self.result = nil      -- nil / "success" / "fail"
    self.resultTimer = 0
    self.RESULT_DURATION = 1.2
    -- 命中反馈
    self.hitFlashTimer = 0
    self.shakeTimer = 0
    return self
end

function SuppressOverlay:onEnter()
end

function SuppressOverlay:onExit()
end

function SuppressOverlay:update(dt)
    if self.result then
        self.resultTimer = self.resultTimer + dt
        if self.resultTimer >= self.RESULT_DURATION then
            ScreenManager.pop()
            return
        end
        return
    end

    SuppressSystem.update(dt)

    -- 检查连续模式超时
    if not SuppressSystem.state.active and not self.result then
        self.result = "fail"
        self.resultTimer = 0
        EventBus.emit("suppress_result", "fail")
    end

    -- 反馈衰减
    if self.hitFlashTimer > 0 then self.hitFlashTimer = self.hitFlashTimer - dt end
    if self.shakeTimer > 0 then self.shakeTimer = self.shakeTimer - dt end
end

function SuppressOverlay:onInput(action, sx, sy)
    if self.result then return true end

    if action == "down" then
        local tapResult = SuppressSystem.tap()
        if tapResult == "success" then
            self.result = "success"
            self.resultTimer = 0
            self.hitFlashTimer = 0.3
            EventBus.emit("suppress_result", "success")
        elseif tapResult == "fail" then
            self.result = "fail"
            self.resultTimer = 0
            self.shakeTimer = 0.15
        elseif tapResult == "hit" then
            self.hitFlashTimer = 0.3
            self.shakeTimer = 0.08
        end
        return true
    end
    return true
end

function SuppressOverlay:render(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state

    -- 震屏偏移
    local ox, oy = 0, 0
    if self.shakeTimer > 0 then
        ox = math.sin(t * 40) * 4
        oy = math.cos(t * 50) * 3
    end
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)

    -- 半透明墨色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, -10, -10, logW + 20, logH + 20)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.70))
    nvgFill(vg)

    -- 异兽名
    local qualColor = P.qualColor(self.beast.quality)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, 0.9))
    local nameStr = "【" .. self.beast.quality .. "·" .. self.beast.name .. "】"
    nvgText(vg, logW * 0.5, logH * 0.25, nameStr)

    -- 命中闪光
    if self.hitFlashTimer > 0 then
        local fa = (self.hitFlashTimer / 0.3) * 0.30
        nvgBeginPath(vg)
        nvgCircle(vg, logW * 0.5, logH * 0.45, 120)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, fa))
        nvgFill(vg)
    end

    if not self.result then
        if s.mode == SuppressSystem.MODE_TIMING then
            self:renderTimingMode(vg, logW, logH, t)
        else
            self:renderRapidMode(vg, logW, logH, t)
        end
    else
        self:renderResult(vg, logW, logH, t)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- 时机模式渲染
------------------------------------------------------------

function SuppressOverlay:renderTimingMode(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state

    local barW = logW * 0.6
    local barH = 18
    local barX = (logW - barW) * 0.5
    local barY = logH * 0.45

    -- 横条底
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50))
    nvgFill(vg)

    -- 目标区
    local tz1 = s.targetZone[1]
    local tz2 = s.targetZone[2]
    local tzX = barX + tz1 * barW
    local tzW = (tz2 - tz1) * barW
    local pulseAlpha = 0.40 + math.sin(t * 4) * 0.10
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tzX, barY, tzW, barH, 2)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, pulseAlpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.70))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 指针
    local pointerX = barX + s.pointer * barW
    nvgBeginPath(vg)
    nvgMoveTo(vg, pointerX, barY - 2)
    nvgLineTo(vg, pointerX, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    -- 顶端墨点
    nvgBeginPath(vg)
    nvgCircle(vg, pointerX, barY - 4, 5)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85))
    nvgFill(vg)

    -- 命中计数
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.8))
    local hitStr = "封印 " .. s.hitCount .. "/" .. s.requiredHits
    nvgText(vg, logW * 0.5, barY + barH + 16, hitStr)
end

------------------------------------------------------------
-- 连续模式渲染
------------------------------------------------------------

function SuppressOverlay:renderRapidMode(vg, logW, logH, t)
    local P = InkPalette
    local s = SuppressSystem.state

    local cx = logW * 0.5
    local cy = logH * 0.45

    -- 底环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 55)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.30))
    nvgStrokeWidth(vg, 15)
    nvgStroke(vg)

    -- 进度弧
    local progress = SuppressSystem.getRapidProgress()
    if progress > 0 then
        local endAngle = -math.pi * 0.5 + math.pi * 2 * progress
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, 55, -math.pi * 0.5, endAngle, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.60))
        nvgStrokeWidth(vg, 15)
        nvgStroke(vg)
    end

    -- 中央计数
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgText(vg, cx, cy, tostring(s.tapCount))

    -- 倒计时条
    local timerBarW = logW * 0.4
    local timerBarH = 6
    local timerBarX = (logW - timerBarW) * 0.5
    local timerBarY = cy + 80
    local timeRatio = SuppressSystem.getRapidTimeRatio()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, timerBarX, timerBarY, timerBarW, timerBarH, 3)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.25))
    nvgFill(vg)

    -- 渐变条: jade → cinnabar
    local fillW = timerBarW * timeRatio
    if fillW > 0 then
        local lr = P.jade.r + (P.cinnabar.r - P.jade.r) * (1 - timeRatio)
        local lg = P.jade.g + (P.cinnabar.g - P.jade.g) * (1 - timeRatio)
        local lb = P.jade.b + (P.cinnabar.b - P.jade.b) * (1 - timeRatio)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, timerBarX, timerBarY, fillW, timerBarH, 3)
        nvgFillColor(vg, nvgRGBAf(lr, lg, lb, 0.7))
        nvgFill(vg)
    end
end

------------------------------------------------------------
-- 结果渲染
------------------------------------------------------------

function SuppressOverlay:renderResult(vg, logW, logH, t)
    local P = InkPalette
    local alpha = math.min(1, self.resultTimer / 0.3)

    local text, color
    if self.result == "success" then
        text = "压制成功"
        color = P.jade
    else
        text = "压制失败"
        color = P.cinnabar
    end

    -- 墨晕光环
    BrushStrokes.inkWash(vg, logW * 0.5, logH * 0.45, 20, 80, color, alpha * 0.25)

    -- 结果文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, alpha * 0.9))
    nvgText(vg, logW * 0.5, logH * 0.45, text)
end

return SuppressOverlay
