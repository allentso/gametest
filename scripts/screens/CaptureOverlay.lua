--- CaptureOverlay - 捕获演出（电影级揭示动画 + 异兽信息卡）
--- 4阶段: 墨染扩散→金光乍现→符文浮现→品质+形态+描述揭晓
--- 首次捕获 6.5s（可点击跳过），重复捕获 4.5s
local InkPalette = require("data.InkPalette")
local ScreenManager = require("systems.ScreenManager")
local BrushStrokes = require("render.BrushStrokes")
local CaptureSystem = require("systems.CaptureSystem")
local BeastRenderer = require("render.BeastRenderer")
local BeastData = require("data.BeastData")
local GameState = require("systems.GameState")

local CaptureOverlay = {}
CaptureOverlay.__index = CaptureOverlay

-- 阶段时间
local PHASE_INK     = { s = 0.0, e = 1.0 }
local PHASE_FLASH   = { s = 0.8, e = 2.0 }
local PHASE_RUNE    = { s = 1.8, e = 3.2 }
local PHASE_REVEAL  = { s = 2.8 }

-- 首次捕获可点击跳过的最短等待
local SKIP_AFTER = 3.5

function CaptureOverlay.new(params)
    local self = setmetatable({}, CaptureOverlay)
    self.isModal = true
    self.beast = params.beast
    self.contract = params.contract
    self.elapsed = 0
    self.quality = params.beast.quality or "R"
    self.variant = params.contract and params.contract.variant or "normal"
    self.variantName = CaptureSystem.VARIANT_NAMES[self.variant] or "普通"

    -- 查询 BeastData 获取 desc
    self.beastDesc = nil
    for _, bd in ipairs(BeastData) do
        if bd.id == self.beast.id then
            self.beastDesc = bd.desc
            break
        end
    end

    -- 首次捕获检测（bestiary 在 settleSession 才更新，此时为 pre-session 状态）
    local entry = GameState.data.bestiary[self.beast.id]
    self.isFirstCapture = (entry == nil) or (not entry.captured)

    -- 时长：首次多给 2s 阅读时间
    self.duration = self.isFirstCapture and 6.5 or 4.5

    return self
end

function CaptureOverlay:onEnter()
end

function CaptureOverlay:onExit()
end

function CaptureOverlay:update(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.duration then
        ScreenManager.pop()
    end
end

function CaptureOverlay:onInput(action, sx, sy)
    -- 首次捕获：播放 SKIP_AFTER 秒后允许点击跳过
    if self.isFirstCapture and self.elapsed > SKIP_AFTER then
        if action == "tap" or action == "down" then
            ScreenManager.pop()
            return true
        end
    end
    -- 其余情况吞掉输入
    return true
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function CaptureOverlay:render(vg, logW, logH, t)
    local P = InkPalette
    local e = self.elapsed
    local cx = logW * 0.5
    local cy = logH * 0.38

    local qualColor = P.qualColor(self.quality)
    local rayCount = ({ R = 4, SR = 8, SSR = 12 })[self.quality] or 4
    local particleCount = ({ R = 6, SR = 12, SSR = 24 })[self.quality] or 6
    local rotSpeed = ({ R = 0.5, SR = 1.0, SSR = 2.0 })[self.quality] or 0.5

    -- Phase 1: 墨染扩散 (0 ~ 1.0s)
    if e >= PHASE_INK.s and e < PHASE_INK.e + 0.5 then
        local p = self:easeOutCubic(math.min(1, (e - PHASE_INK.s) / (PHASE_INK.e - PHASE_INK.s)))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85 * math.min(1, p * 2)))
        nvgFill(vg)
        local radius = p * math.max(logW, logH) * 0.4
        BrushStrokes.inkWash(vg, cx, cy, radius * 0.2, radius, P.inkDark, 0.5 * p)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85))
        nvgFill(vg)
    end

    -- Phase 2: 金光乍现 (0.8 ~ 2.0s)
    if e >= PHASE_FLASH.s and e <= PHASE_FLASH.e then
        local p = (e - PHASE_FLASH.s) / (PHASE_FLASH.e - PHASE_FLASH.s)
        local flashAlpha = math.sin(p * math.pi) * 0.6

        for i = 0, rayCount - 1 do
            local angle = (i / rayCount) * math.pi * 2 + t * rotSpeed
            local len = 60 + p * 120
            local ex2 = cx + math.cos(angle) * len
            local ey2 = cy + math.sin(angle) * len
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, ex2, ey2)
            nvgStrokeColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, flashAlpha * 0.5))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        BrushStrokes.inkWash(vg, cx, cy, 30, 90, qualColor, flashAlpha * 0.3)

        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 15 + p * 10)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, flashAlpha * 0.7))
        nvgFill(vg)
    end

    -- Phase 3: 符文浮现 (1.8 ~ 3.2s)
    if e >= PHASE_RUNE.s and e <= PHASE_RUNE.e then
        local p = (e - PHASE_RUNE.s) / (PHASE_RUNE.e - PHASE_RUNE.s)

        for i = 0, particleCount - 1 do
            local angle = (i / particleCount) * math.pi * 2 + t * rotSpeed * 0.5
            local dist = 50 + math.sin(t * 2 + i) * 20
            local px = cx + math.cos(angle) * dist
            local py = cy + math.sin(angle) * dist
            local pAlpha = p * 0.5 * (0.5 + 0.5 * math.sin(t * 3 + i * 0.7))
            BrushStrokes.inkDotStable(vg, px, py, 3, qualColor, pAlpha, i * 17)
        end

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
            local firstChar = string.sub(self.beast.name, 1, 3)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 56)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, charAlpha * 0.8))
            nvgText(vg, cx, cy, firstChar)
        end
    end

    -- Phase 4: 品质+形态+描述揭晓 (2.8s ~ end)
    if e >= PHASE_REVEAL.s then
        local p = math.min(1, (e - PHASE_REVEAL.s) / 1.0)

        -- 暖纸色卡片背景（与图鉴风格一致）
        local cardW = math.min(logW * 0.88, 340)
        local cardH = logH * 0.72
        local cardX = (logW - cardW) * 0.5
        local cardTop = cy - cardH * 0.38
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cardTop, cardW, cardH, 8)
        nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.96 * p))
        nvgFill(vg)
        BrushStrokes.inkRect(vg, cardX, cardTop, cardW, cardH, P.inkMedium, 0.35 * p, 55)

        -- 异兽形态（贴图优先，矢量降级）
        if p > 0.1 then
            local shapeAlpha = math.min(1, (p - 0.1) / 0.6)
            nvgSave(vg)
            nvgGlobalAlpha(vg, shapeAlpha)
            if not BeastRenderer.drawImage(vg, self.beast.id, cx, cy, 120, 1.0, self.variant) then
                -- 无贴图：矢量降级
                ---@type table
                local drawBeast = {
                    bodySize = self.beast.bodySize or 0.55,
                    quality = self.quality,
                    type = self.beast.type or self.beast.id,
                    id = self.beast.id,
                    variant = self.variant,
                    aiState = "idle",
                }
                BeastRenderer.draw(vg, drawBeast, cx, cy, 85, t)
            end
            nvgRestore(vg)
        end

        -- 品质光环（形态周围的微弱光晕）
        local glowAlpha = p * 0.15
        BrushStrokes.inkWash(vg, cx, cy, 20, 60, qualColor, glowAlpha)

        -- 名称（形态下方）
        local infoY = cy + 55
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, p * 0.90))
        nvgText(vg, cx, infoY, self.beast.name)

        -- 品质标签
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, p * 0.9))
        nvgText(vg, cx, infoY + 26, self.quality)

        -- 变体标签（非普通时显示）
        local variantLineY = infoY + 26
        if self.variant ~= "normal" and p > 0.3 then
            local vAlpha = math.min(1, (p - 0.3) / 0.5)
            local varColors = {
                yiwen         = P.jade,
                xuancai       = P.indigo,
                xuancai_yiwen = P.gold,
            }
            local vc = varColors[self.variant] or P.inkMedium
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBAf(vc.r, vc.g, vc.b, vAlpha * 0.9))
            nvgText(vg, cx, infoY + 46, "· " .. self.variantName .. " ·")
            variantLineY = infoY + 46
        end

        -- 描述文字（山海经原文）
        if self.beastDesc and p > 0.4 then
            local descAlpha = math.min(1, (p - 0.4) / 0.6)
            local descY = variantLineY + 28
            local descW = math.min(logW * 0.75, 280)

            -- 引号装饰
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, descAlpha * 0.25))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(vg, cx - descW * 0.5 - 4, descY - 6, '“')
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

            -- 描述正文
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, descAlpha * 0.65))
            nvgTextBox(vg, cx - descW * 0.5, descY, descW, self.beastDesc)
        end

        -- 首次收录标记
        if self.isFirstCapture and p > 0.7 then
            local firstAlpha = math.min(1, (p - 0.7) / 0.3)
            local firstY = cardTop + cardH - 36

            -- 分隔线
            local lineW = 80
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - lineW, firstY - 12)
            nvgLineTo(vg, cx + lineW, firstY - 12)
            nvgStrokeWidth(vg, 0.8)
            nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, firstAlpha * 0.35))
            nvgStroke(vg)

            -- 首次收录文字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 15)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, firstAlpha * 0.85))
            nvgText(vg, cx, firstY + 4, "首次收录 · 图鉴已更新")
        end

        -- SSR 独有描述（仅非首次时显示，首次由 desc 承担信息量）
        if self.quality == "SSR" and not self.isFirstCapture and p > 0.5 then
            local descAlpha2 = (p - 0.5) / 0.5
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, descAlpha2 * 0.7))
            nvgText(vg, cx, cardTop + cardH - 36, "天命之契 · 不朽灵印")
        end

        -- 点击继续提示（首次捕获，SKIP_AFTER 秒后显示）
        if self.isFirstCapture and e > SKIP_AFTER then
            local hintAlpha = 0.4 + math.sin(t * 2.5) * 0.15
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, hintAlpha))
            nvgText(vg, cx, cardTop + cardH - 10, "点击继续探索")
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
