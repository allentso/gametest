--- 锻造坊屏 - 封灵器合成
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local CraftSystem = require("systems.CraftSystem")

local CraftScreen = {}
CraftScreen.__index = CraftScreen

function CraftScreen.new(params)
    local self = setmetatable({}, CraftScreen)
    self.fadeIn = 0
    self.t = 0
    self.buttons = {}
    self.craftAnim = nil  -- { recipeId, timer }
    return self
end

function CraftScreen:onEnter()
    self.fadeIn = 0
end

function CraftScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
    -- 合成动画
    if self.craftAnim then
        self.craftAnim.timer = self.craftAnim.timer + dt
        if self.craftAnim.timer > 0.6 then
            self.craftAnim = nil
        end
    end
end

function CraftScreen:render(vg, logW, logH, t)
    local alpha = self.fadeIn
    local p = InkPalette.paper

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 1.0))
    nvgFill(vg)

    -- 标题
    nvgFontSize(vg, 22)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.05, "锻造坊")

    -- 返回
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.65 * alpha))
    nvgText(vg, 16, logH * 0.05, "< 返回")

    -- 顶部资源栏
    local resY = logH * 0.11
    local resources = {
        { name = "灵石", key = "lingshi", color = InkPalette.jade },
        { name = "兽魂", key = "shouhun", color = InkPalette.azure },
        { name = "天晶", key = "tianjing", color = InkPalette.gold },
    }
    local rStartX = logW * 0.1
    local rGap = logW * 0.27
    for i, res in ipairs(resources) do
        local rx = rStartX + (i - 1) * rGap
        nvgBeginPath(vg)
        nvgCircle(vg, rx, resY, 3.5)
        nvgFillColor(vg, nvgRGBAf(res.color.r, res.color.g, res.color.b, 0.65 * alpha))
        nvgFill(vg)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.75 * alpha))
        nvgText(vg, rx + 8, resY,
            string.format("%s %d", res.name, GameState.getResource(res.key)))
    end

    -- 分隔线
    BrushStrokes.inkLine(vg, logW * 0.1, resY + 16, logW * 0.9, resY + 16,
        1.0, InkPalette.inkWash, 0.20 * alpha, 55)

    -- 资源拼音→中文名映射
    local RES_NAMES = {
        lingshi = "灵石", shouhun = "兽魂", tianjing = "天晶",
    }

    -- 合成卡片
    self.buttons = {}
    local cardW = logW * 0.85
    local cardH = logH * 0.18
    local cardX = (logW - cardW) * 0.5
    local startY = logH * 0.20
    local cardGap = 16

    for i, recipe in ipairs(CraftSystem.recipes) do
        local cy = startY + (i - 1) * (cardH + cardGap)
        local canCraft = CraftSystem.canCraft(recipe.id, GameState.data)

        -- 合成动画辉光
        local glowAlpha = 0
        if self.craftAnim and self.craftAnim.recipeId == recipe.id then
            glowAlpha = math.sin(self.craftAnim.timer / 0.6 * math.pi) * 0.2
        end

        -- 卡片底
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b,
            (0.06 + glowAlpha) * alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b, 0.35 * alpha))
        nvgStroke(vg)

        -- 名称
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.80 * alpha))
        nvgText(vg, cardX + 12, cy + cardH * 0.25, recipe.name)

        -- 等级
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b, 0.60 * alpha))
        nvgText(vg, cardX + 12, cy + cardH * 0.50,
            string.format("T%d · 捕获率 %d%%", i + 1, ({85, 92, 98})[i] or 85))

        -- 消耗（中文显示）
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.60 * alpha))
        local costParts = {}
        for resKey, amount in pairs(recipe.cost) do
            local resName = RES_NAMES[resKey] or resKey
            table.insert(costParts, string.format("%s×%d", resName, amount))
        end
        nvgText(vg, cardX + 12, cy + cardH * 0.75, "消耗: " .. table.concat(costParts, "  "))

        -- 库存
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, 0.55 * alpha))
        nvgText(vg, cardX + cardW - 80, cy + cardH * 0.25,
            string.format("已有: %d", GameState.getResource(recipe.result)))

        -- 合成按钮
        local btnW = 60
        local btnH = 28
        local btnX = cardX + cardW - btnW - 10
        local btnY = cy + cardH * 0.55
        local btnColor = canCraft and InkPalette.jade or InkPalette.inkWash

        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBAf(btnColor.r, btnColor.g, btnColor.b, 0.12 * alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 4)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(btnColor.r, btnColor.g, btnColor.b, 0.50 * alpha))
        nvgStroke(vg)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(btnColor.r, btnColor.g, btnColor.b, 0.75 * alpha))
        nvgText(vg, btnX + btnW * 0.5, btnY + btnH * 0.5, "锻造")

        table.insert(self.buttons, {
            type = "craft", recipeId = recipe.id,
            x = btnX, y = btnY, w = btnW, h = btnH, canCraft = canCraft
        })
    end

    -- 返回按钮区域
    table.insert(self.buttons, { type = "back", x = 0, y = logH * 0.02, w = 80, h = 30 })
end

function CraftScreen:onInput(action, sx, sy)
    if action ~= "tap" then return false end

    for _, btn in ipairs(self.buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then
            if btn.type == "craft" and btn.canCraft then
                local success = CraftSystem.craft(btn.recipeId, GameState.data)
                if success then
                    GameState.save()
                    self.craftAnim = { recipeId = btn.recipeId, timer = 0 }
                end
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

return CraftScreen
