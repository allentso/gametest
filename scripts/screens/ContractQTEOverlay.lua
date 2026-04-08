--- ContractQTEOverlay - 灵契震荡 QTE 模态覆盖层
--- 撤离时触发的灵契稳固挑战
--- 3阶段: 预警→QTE→结果
local InkPalette = require("data.InkPalette")
local EvacuationSystem = require("systems.EvacuationSystem")
local ScreenManager = require("systems.ScreenManager")
local BrushStrokes = require("render.BrushStrokes")

local ContractQTEOverlay = {}
ContractQTEOverlay.__index = ContractQTEOverlay

function ContractQTEOverlay.new(params)
    local self = setmetatable({}, ContractQTEOverlay)
    self.isModal = true
    self.contracts = params.contracts
    self.phase = "warning"  -- warning / qte / result
    self.resultTimer = 0
    self.RESULT_DURATION = 1.5
    self.shakeTimer = 0
    return self
end

function ContractQTEOverlay:onEnter()
end

function ContractQTEOverlay:onExit()
end

function ContractQTEOverlay:update(dt)
    local qte = EvacuationSystem.contractQTE

    if self.phase == "warning" then
        if qte.warningTimer <= 0 then
            self.phase = "qte"
        end
    elseif self.phase == "qte" then
        if not qte.active then
            self.phase = "result"
            self.resultTimer = 0
        end
    elseif self.phase == "result" then
        self.resultTimer = self.resultTimer + dt
        if self.resultTimer >= self.RESULT_DURATION then
            ScreenManager.pop()
        end
    end

    EvacuationSystem.updateContractQTE(dt)

    if self.shakeTimer > 0 then
        self.shakeTimer = self.shakeTimer - dt
    end
end

function ContractQTEOverlay:onInput(action, sx, sy)
    if self.phase == "result" then return true end

    if action == "down" then
        if self.phase == "qte" then
            EvacuationSystem.tapContractQTE()
            self.shakeTimer = 0.1
        end
        return true
    end
    return true
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function ContractQTEOverlay:render(vg, logW, logH, t)
    local P = InkPalette
    local qte = EvacuationSystem.contractQTE

    -- 震屏
    local ox, oy = 0, 0
    if self.shakeTimer > 0 then
        ox = math.sin(t * 40) * 3
        oy = math.cos(t * 50) * 2
    end
    nvgSave(vg)
    nvgTranslate(vg, ox, oy)

    -- 墨色遮罩
    nvgBeginPath(vg)
    nvgRect(vg, -10, -10, logW + 20, logH + 20)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.75))
    nvgFill(vg)

    if self.phase == "warning" then
        self:renderWarning(vg, logW, logH, t, qte)
    elseif self.phase == "qte" then
        self:renderQTE(vg, logW, logH, t, qte)
    else
        self:renderResult(vg, logW, logH, t, qte)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- 预警阶段
------------------------------------------------------------

function ContractQTEOverlay:renderWarning(vg, logW, logH, t, qte)
    local P = InkPalette
    local cx = logW * 0.5
    local cy = logH * 0.40

    -- 朱砂闪烁环
    local ringAlpha = 0.3 + math.sin(t * 6) * 0.2
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 60)
    nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, ringAlpha))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.9))
    local titleStr = "灵契震荡 (" .. qte.currentIdx .. "/" .. #qte.contracts .. ")"
    nvgText(vg, cx, cy - 20, titleStr)

    -- 异兽名
    local contract = qte.contracts[qte.currentIdx]
    if contract then
        local qualColor = P.qualColor(contract.quality)
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, 0.9))
        nvgText(vg, cx, cy + 10, contract.name)
    end
end

------------------------------------------------------------
-- QTE 阶段 (时机模式)
------------------------------------------------------------

function ContractQTEOverlay:renderQTE(vg, logW, logH, t, qte)
    local P = InkPalette
    local cx = logW * 0.5

    -- 当前异兽名
    local contract = qte.contracts[qte.currentIdx]
    if contract then
        local qualColor = P.qualColor(contract.quality)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, 0.8))
        nvgText(vg, cx, logH * 0.28, contract.name)
    end

    -- 进度
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
    local progStr = qte.currentIdx .. "/" .. #qte.contracts
    nvgText(vg, cx, logH * 0.32, progStr)

    -- 横条 QTE
    local barW = logW * 0.6
    local barH = 18
    local barX = (logW - barW) * 0.5
    local barY = logH * 0.45

    -- 横条底
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50))
    nvgFill(vg)

    -- 左右危险区 (cinnabar 线性渐变)
    local tz1 = qte.targetZone[1]
    local tz2 = qte.targetZone[2]

    -- 左危险区
    local dangerPaint = nvgLinearGradient(vg, barX, barY,
        barX + tz1 * barW, barY,
        nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.35),
        nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.05))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, tz1 * barW, barH, 4)
    nvgFillPaint(vg, dangerPaint)
    nvgFill(vg)

    -- 右危险区
    local rightX = barX + tz2 * barW
    local dangerPaintR = nvgLinearGradient(vg, rightX, barY,
        barX + barW, barY,
        nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.05),
        nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.35))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, rightX, barY, barW * (1 - tz2), barH, 4)
    nvgFillPaint(vg, dangerPaintR)
    nvgFill(vg)

    -- 目标区
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
    local pointerX = barX + qte.pointer * barW
    nvgBeginPath(vg)
    nvgMoveTo(vg, pointerX, barY - 2)
    nvgLineTo(vg, pointerX, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.9))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, pointerX, barY - 4, 5)
    nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.85))
    nvgFill(vg)
end

------------------------------------------------------------
-- 结果阶段
------------------------------------------------------------

function ContractQTEOverlay:renderResult(vg, logW, logH, t, qte)
    local P = InkPalette
    local cx = logW * 0.5
    local alpha = math.min(1, self.resultTimer / 0.4)

    local lostCount = #qte.lostContracts

    if lostCount == 0 then
        -- 全部稳固
        BrushStrokes.inkWash(vg, cx, logH * 0.42, 20, 80, P.jade, alpha * 0.25)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, alpha * 0.9))
        nvgText(vg, cx, logH * 0.42, "灵契稳固")
    else
        -- 有丢失
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, alpha * 0.9))
        nvgText(vg, cx, logH * 0.36, "灵契破碎 ×" .. lostCount)

        -- 丢失列表
        nvgFontSize(vg, 14)
        for i, contract in ipairs(qte.lostContracts) do
            local qualColor = P.qualColor(contract.quality)
            nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, alpha * 0.7))
            nvgText(vg, cx, logH * 0.42 + (i - 1) * 22, contract.name .. " 散逸")
        end
    end
end

return ContractQTEOverlay
