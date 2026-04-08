--- 灵兽图鉴屏
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local BeastData = require("data.BeastData")

local BookScreen = {}
BookScreen.__index = BookScreen

function BookScreen.new(params)
    local self = setmetatable({}, BookScreen)
    self.fadeIn = 0
    self.t = 0
    self.scrollY = 0
    self.backBtn = nil
    return self
end

function BookScreen:onEnter()
    self.fadeIn = 0
    self.scrollY = 0
end

function BookScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
end

function BookScreen:render(vg, logW, logH, t)
    local alpha = self.fadeIn
    local p = InkPalette.paper

    -- 宣纸底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 1.0))
    nvgFill(vg)

    -- 标题栏
    nvgFontSize(vg, 22)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.05, "灵兽图鉴")

    -- 返回
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.65 * alpha))
    nvgText(vg, 16, logH * 0.05, "< 返回")
    self.backBtn = { x = 0, y = logH * 0.02, w = 80, h = 30 }

    -- 收录进度
    local collected = GameState.getBestiaryCount()
    local total = #BeastData
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, 0.60 * alpha))
    nvgText(vg, logW - 16, logH * 0.05,
        string.format("收录 %d/%d", collected, total))

    -- 分隔线
    BrushStrokes.inkLine(vg, logW * 0.1, logH * 0.09, logW * 0.9, logH * 0.09,
        1.0, InkPalette.inkWash, 0.20 * alpha, 77)

    -- 卡片列表
    local cardW = logW * 0.85
    local cardH = logH * 0.10
    local cardX = (logW - cardW) * 0.5
    local startY = logH * 0.12 - self.scrollY
    local cardGap = 10

    for i, beast in ipairs(BeastData) do
        local cy = startY + (i - 1) * (cardH + cardGap)
        if cy + cardH < 0 or cy > logH then goto continue end

        local entry = GameState.data.bestiary[beast.id]
        local state = "undiscovered"
        if entry then
            state = entry.captured and "collected" or "encountered"
        end

        -- 卡片底色
        local bgColor, bgAlpha
        if state == "collected" then
            bgColor = InkPalette.gold
            bgAlpha = 0.06
        elseif state == "encountered" then
            bgColor = InkPalette.inkWash
            bgAlpha = 0.08
        else
            bgColor = InkPalette.inkLight
            bgAlpha = 0.06
        end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgFillColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, bgAlpha * alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 6)
        nvgStrokeWidth(vg, 0.8)
        nvgStrokeColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, 0.25 * alpha))
        nvgStroke(vg)

        if state == "undiscovered" then
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkWash.r, InkPalette.inkWash.g, InkPalette.inkWash.b,
                0.40 * alpha))
            nvgText(vg, logW * 0.5, cy + cardH * 0.5, "???")
        elseif state == "encountered" then
            -- 首字符文
            nvgFontSize(vg, 22)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
                0.40 * alpha))
            local firstChar = string.sub(beast.name, 1, 3)  -- UTF-8 first char
            nvgText(vg, cardX + 12, cy + cardH * 0.5, firstChar)
            -- 名称（淡）
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
                0.60 * alpha))
            nvgText(vg, cardX + 45, cy + cardH * 0.5, beast.name)
        else -- collected
            -- 品质标签
            local qColor = InkPalette.qualColor(entry.bestQuality or "R")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(qColor.r, qColor.g, qColor.b, 0.70 * alpha))
            nvgText(vg, cardX + 10, cy + cardH * 0.3, entry.bestQuality or "R")

            -- 名称
            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
                0.80 * alpha))
            nvgText(vg, cardX + 35, cy + cardH * 0.3, beast.name)

            -- 描述
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
                0.55 * alpha))
            nvgText(vg, cardX + 35, cy + cardH * 0.7, beast.desc or "")

            -- 收集次数
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, cardX + cardW - 10, cy + cardH * 0.5,
                string.format("×%d", entry.count or 0))
        end

        ::continue::
    end
end

function BookScreen:onInput(action, sx, sy)
    if action == "tap" and self.backBtn then
        if sx >= self.backBtn.x and sx <= self.backBtn.x + self.backBtn.w
           and sy >= self.backBtn.y and sy <= self.backBtn.y + self.backBtn.h then
            local LobbyScreen = require("screens.LobbyScreen")
            ScreenManager.switch(LobbyScreen)
            return true
        end
    elseif action == "drag_y" then
        self.scrollY = math.max(0, self.scrollY - sy)
        return true
    end
    return false
end

return BookScreen
