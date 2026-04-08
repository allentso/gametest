--- 进场准备屏 - 封灵器选择
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local SessionState = require("systems.SessionState")

local PrepareScreen = {}
PrepareScreen.__index = PrepareScreen

local SEALERS = {
    { id = "sealer_t2", name = "青玉壶",  tier = "T2", rate = "85%",  color = nil },
    { id = "sealer_t3", name = "金缕珠",  tier = "T3", rate = "92%",  color = nil },
    { id = "sealer_t4", name = "天命盘",  tier = "T4", rate = "98%",  color = nil },
}

function PrepareScreen.new(params)
    local self = setmetatable({}, PrepareScreen)
    self.fadeIn = 0
    self.t = 0
    self.selected = {}
    for _, s in ipairs(SEALERS) do
        self.selected[s.id] = 0
    end
    self.buttons = {}
    return self
end

function PrepareScreen:onEnter()
    self.fadeIn = 0
    print("[PrepareScreen] 进入准备")
end

function PrepareScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
end

function PrepareScreen:render(vg, logW, logH, t)
    local alpha = self.fadeIn
    local p = InkPalette.paper

    -- 宣纸底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 1.0))
    nvgFill(vg)

    -- 标题
    nvgFontSize(vg, 24)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.06, "准备出发")

    -- 返回按钮
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
        0.65 * alpha))
    nvgText(vg, 16, logH * 0.06, "< 返回")

    -- 说明
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
        0.60 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.12, "素灵符(免费)×3 已自动装备")

    -- 封灵器卡片
    local cardH = logH * 0.13
    local cardW = logW * 0.8
    local cardX = (logW - cardW) * 0.5
    local startY = logH * 0.18
    local cardGap = 12

    self.buttons = {}

    for i, sealer in ipairs(SEALERS) do
        local cy = startY + (i - 1) * (cardH + cardGap)
        local stock = GameState.getResource(sealer.id)
        local sel = self.selected[sealer.id]

        -- 卡片底色
        local jade = InkPalette.jade
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgFillColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.06 * alpha))
        nvgFill(vg)

        -- 描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.35 * alpha))
        nvgStroke(vg)

        -- 等级徽记
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.70 * alpha))
        nvgText(vg, cardX + 10, cy + cardH * 0.3, sealer.tier)

        -- 名称
        nvgFontSize(vg, 15)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
            0.80 * alpha))
        nvgText(vg, cardX + 35, cy + cardH * 0.3, sealer.name)

        -- 捕获率
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.60 * alpha))
        nvgText(vg, cardX + 35, cy + cardH * 0.7, "捕获率: " .. sealer.rate)

        -- 库存
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, cardX + cardW - 80, cy + cardH * 0.3,
            string.format("库存: %d", stock))

        -- 已选数量
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
            0.85 * alpha))
        nvgText(vg, cardX + cardW - 30, cy + cardH * 0.5, tostring(sel))

        -- 加减按钮区域
        local btnR = 14
        local minusCX = cardX + cardW - 65
        local plusCX = cardX + cardW - 10
        local btnCY = cy + cardH * 0.7

        -- 减按钮
        nvgBeginPath(vg)
        nvgCircle(vg, minusCX, btnCY, btnR)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.45 * alpha))
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.60 * alpha))
        nvgText(vg, minusCX, btnCY, "-")

        -- 加按钮
        nvgBeginPath(vg)
        nvgCircle(vg, plusCX, btnCY, btnR)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.50 * alpha))
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.70 * alpha))
        nvgText(vg, plusCX, btnCY, "+")

        table.insert(self.buttons, {
            type = "minus", sealerId = sealer.id,
            x = minusCX - btnR, y = btnCY - btnR, w = btnR * 2, h = btnR * 2
        })
        table.insert(self.buttons, {
            type = "plus", sealerId = sealer.id,
            x = plusCX - btnR, y = btnCY - btnR, w = btnR * 2, h = btnR * 2
        })
    end

    -- 底部主按钮
    local mainBtnW = 180
    local mainBtnH = 44
    local mainBtnX = (logW - mainBtnW) * 0.5
    local mainBtnY = logH * 0.82
    local breathe = 1.0 + math.sin(self.t * 2) * 0.03

    nvgBeginPath(vg)
    nvgRoundedRect(vg, mainBtnX, mainBtnY, mainBtnW * breathe, mainBtnH, 6)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b,
        0.15 * alpha))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mainBtnX, mainBtnY, mainBtnW * breathe, mainBtnH, 6)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b,
        0.65 * alpha))
    nvgStroke(vg)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b,
        0.85 * alpha))
    nvgText(vg, logW * 0.5, mainBtnY + mainBtnH * 0.5, "踏入灵境")

    table.insert(self.buttons, {
        type = "enter",
        x = mainBtnX, y = mainBtnY, w = mainBtnW, h = mainBtnH
    })

    -- 返回按钮区域
    table.insert(self.buttons, {
        type = "back", x = 0, y = logH * 0.03, w = 80, h = 30
    })
end

function PrepareScreen:onInput(action, sx, sy)
    if action ~= "tap" then return false end

    for _, btn in ipairs(self.buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then
            if btn.type == "plus" then
                local stock = GameState.getResource(btn.sealerId)
                if self.selected[btn.sealerId] < stock then
                    self.selected[btn.sealerId] = self.selected[btn.sealerId] + 1
                end
                return true
            elseif btn.type == "minus" then
                if self.selected[btn.sealerId] > 0 then
                    self.selected[btn.sealerId] = self.selected[btn.sealerId] - 1
                end
                return true
            elseif btn.type == "enter" then
                -- 扣减封灵器并进入探索
                SessionState.reset()
                for id, count in pairs(self.selected) do
                    if count > 0 then
                        GameState.spendResource(id, count)
                        SessionState.addItem(id, count)
                    end
                end
                GameState.save()

                local ExploreScreen = require("screens.ExploreScreen")
                ScreenManager.switch(ExploreScreen)
                return true
            elseif btn.type == "back" then
                local LobbyScreen = require("screens.LobbyScreen")
                ScreenManager.switch(LobbyScreen)
                return true
            end
        end
    end
    return false
end

return PrepareScreen
