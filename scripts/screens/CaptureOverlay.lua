--- CaptureOverlay - 捕获演出（4.5秒电影级揭示动画）
--- 4阶段: 墨染扩散→金光乍现→符文浮现→品质+变体揭晓
local InkPalette = require("data.InkPalette")
local ScreenManager = require("systems.ScreenManager")
local BrushStrokes = require("render.BrushStrokes")
local CaptureSystem = require("systems.CaptureSystem")

local CaptureOverlay = {}
CaptureOverlay.__index = CaptureOverlay

local TOTAL_DURATION = 4.5

-- 阶段时间
local PHASE_INK     = { s = 0.0, e = 1.0 }
local PHASE_FLASH   = { s = 0.8, e = 2.0 }
local PHASE_RUNE    = { s = 1.8, e = 3.2 }
local PHASE_REVEAL  = { s = 2.8, e = 4.5 }

function CaptureOverlay.new(params)
    local self = setmetatable({}, CaptureOverlay)
    self.isModal = true
    self.beast = params.beast
    self.contract = params.contract
    self.elapsed = 0
    self.quality = params.beast.quality or "R"
    self.variant = params.contract and params.contract.variant or "normal"
    self.variantName = CaptureSystem.VARIANT_NAMES[self.variant] or "普通"
    return self
end

function CaptureOverlay:onEnter()
end

function CaptureOverlay:onExit()
end

function CaptureOverlay:update(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= TOTAL_DURATION then
        ScreenManager.pop()
    end
end

function CaptureOverlay:onInput(action, sx, sy)
    -- 不可跳过
    return true
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function CaptureOverlay:render(vg, logW, logH, t)
    local P = InkPalette
    local e = self.elapsed
    local cx = logW * 0.5
    local cy = logH * 0.45

    local qualColor = P.qualColor(self.quality)
    local rayCount = ({ R = 4, SR = 8, SSR = 12 })[self.quality] or 4
    local particleCount = ({ R = 6, SR = 12, SSR = 24 })[self.quality] or 6
    local rotSpeed = ({ R = 0.5, SR = 1.0, SSR = 2.0 })[self.quality] or 0.5

    -- Phase 1: 墨染扩散 (0 ~ 1.0s)
    if e >= PHASE_INK.s and e < PHASE_INK.e + 0.5 then
        local p = self:easeOutCubic(math.min(1, (e - PHASE_INK.s) / (PHASE_INK.e - PHASE_INK.s)))
        -- 全屏暗色
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85 * math.min(1, p * 2)))
        nvgFill(vg)
        -- 中心墨圈扩散
        local radius = p * math.max(logW, logH) * 0.4
        BrushStrokes.inkWash(vg, cx, cy, radius * 0.2, radius, P.inkDark, 0.5 * p)
    else
        -- 保持全屏暗色
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85))
        nvgFill(vg)
    end

    -- Phase 2: 金光乍现 (0.8 ~ 2.0s)
    if e >= PHASE_FLASH.s and e <= PHASE_FLASH.e then
        local p = (e - PHASE_FLASH.s) / (PHASE_FLASH.e - PHASE_FLASH.s)
        local flashAlpha = math.sin(p * math.pi) * 0.6

        -- 放射线
        for i = 0, rayCount - 1 do
            local angle = (i / rayCount) * math.pi * 2 + t * rotSpeed
            local len = 60 + p * 120
            local ex = cx + math.cos(angle) * len
            local ey = cy + math.sin(angle) * len
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, ex, ey)
            nvgStrokeColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, flashAlpha * 0.5))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 外环光晕
        BrushStrokes.inkWash(vg, cx, cy, 30, 90, qualColor, flashAlpha * 0.3)

        -- 内核光球
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 15 + p * 10)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, flashAlpha * 0.7))
        nvgFill(vg)
    end

    -- Phase 3: 符文浮现 (1.8 ~ 3.2s)
    if e >= PHASE_RUNE.s and e <= PHASE_RUNE.e then
        local p = (e - PHASE_RUNE.s) / (PHASE_RUNE.e - PHASE_RUNE.s)

        -- 浮动粒子
        for i = 0, particleCount - 1 do
            local angle = (i / particleCount) * math.pi * 2 + t * rotSpeed * 0.5
            local dist = 50 + math.sin(t * 2 + i) * 20
            local px = cx + math.cos(angle) * dist
            local py = cy + math.sin(angle) * dist
            local pAlpha = p * 0.5 * (0.5 + 0.5 * math.sin(t * 3 + i * 0.7))
            BrushStrokes.inkDotStable(vg, px, py, 3, qualColor, pAlpha, i * 17)
        end

        -- 双环旋转
        local ringAlpha = p * 0.4
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, 45, t * rotSpeed, t * rotSpeed + math.pi * 1.5, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, ringAlpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, 55, -t * rotSpeed * 0.7, -t * rotSpeed * 0.7 + math.pi * 1.2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, ringAlpha * 0.6))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 中央异兽名首字
        if p > 0.3 then
            local charAlpha = math.min(1, (p - 0.3) / 0.4)
            local firstChar = string.sub(self.beast.name, 1, 3) -- UTF8 中文 3 bytes
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 56)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, charAlpha * 0.8))
            nvgText(vg, cx, cy, firstChar)
        end
    end

    -- Phase 4: 品质+变体揭晓 (2.8 ~ 4.5s)
    if e >= PHASE_REVEAL.s then
        local p = math.min(1, (e - PHASE_REVEAL.s) / 1.0)

        -- 异兽全名
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, p * 0.9))
        nvgText(vg, cx, cy + 50, self.beast.name)

        -- 品质标签
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, p * 0.9))
        nvgText(vg, cx, cy + 80, self.quality)

        -- 变体标签（非普通时显示）
        if self.variant ~= "normal" and p > 0.3 then
            local vAlpha = math.min(1, (p - 0.3) / 0.5)
            local varColors = {
                yiwen         = P.jade,
                xuancai       = P.indigo,
                xuancai_yiwen = P.gold,
            }
            local vc = varColors[self.variant] or P.inkMedium
            nvgFontSize(vg, 15)
            nvgFillColor(vg, nvgRGBAf(vc.r, vc.g, vc.b, vAlpha * 0.9))
            nvgText(vg, cx, cy + 102, "· " .. self.variantName .. " ·")
        end

        -- SSR 独有描述
        if self.quality == "SSR" and p > 0.5 then
            local descAlpha = (p - 0.5) / 0.5
            local descY = self.variant ~= "normal" and (cy + 124) or (cy + 105)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, descAlpha * 0.7))
            nvgText(vg, cx, descY, "天命之契·不朽灵印")
        end
    end
end

------------------------------------------------------------
-- 缓动函数
------------------------------------------------------------

function CaptureOverlay:easeOutCubic(x)
    return 1 - (1 - x) ^ 3
end

return CaptureOverlay
