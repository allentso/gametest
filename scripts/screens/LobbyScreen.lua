--- 大厅屏幕 - 水墨山景 + 四个导航入口
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local Config = require("Config")

local LobbyScreen = {}
LobbyScreen.__index = LobbyScreen

function LobbyScreen.new(params)
    local self = setmetatable({}, LobbyScreen)
    self.fadeIn = 0
    self.t = 0
    self.buttons = {}
    return self
end

function LobbyScreen:onEnter()
    self.fadeIn = 0
    self.t = 0
    print("[LobbyScreen] 进入大厅")
end

function LobbyScreen:onExit()
    print("[LobbyScreen] 离开大厅")
end

function LobbyScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
end

function LobbyScreen:render(vg, logW, logH, t)
    local alpha = self.fadeIn
    local p = InkPalette.paper

    -- 全屏宣纸底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 1.0))
    nvgFill(vg)

    -- 远景水墨山景（底部82%高度）
    self:drawMountains(vg, logW, logH, t, alpha)

    -- 标题
    local titleY = logH * 0.12
    nvgFontSize(vg, 34)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.90 * alpha))
    nvgText(vg, logW * 0.5, titleY, "山海异闻录")

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
        0.70 * alpha))
    nvgText(vg, logW * 0.5, titleY + 28, "— 寻 光 —")

    -- 资源栏
    local resY = logH * 0.25
    self:drawResources(vg, logW, resY, alpha)

    -- 分隔线
    BrushStrokes.inkLine(vg, logW * 0.15, resY + 22, logW * 0.85, resY + 22,
        1.2, InkPalette.inkWash, 0.22 * alpha, 42)

    -- 四个导航按钮
    local btnY = logH * 0.42
    local btnH = 44
    local btnGap = 14
    local btnW = math.min(logW * 0.6, 220)
    local btnX = (logW - btnW) * 0.5

    local buttons = {
        { text = "踏入灵境", color = InkPalette.cinnabar, screen = "prepare", breathe = true },
        { text = "灵兽图鉴", color = InkPalette.azure,    screen = "book" },
        { text = "锻造坊",   color = InkPalette.jade,     screen = "craft" },
        { text = "每日修行", color = InkPalette.gold,      screen = "daily" },
    }

    self.buttons = {}
    for i, btn in ipairs(buttons) do
        local by = btnY + (i - 1) * (btnH + btnGap)
        local breatheScale = 1.0
        if btn.breathe then
            breatheScale = 1.0 + math.sin(self.t * 2) * 0.03
        end

        local bw = btnW * breatheScale
        local bx = (logW - bw) * 0.5

        -- 按钮底色
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, btnH, 6)
        nvgFillColor(vg, nvgRGBAf(btn.color.r, btn.color.g, btn.color.b, 0.10 * alpha))
        nvgFill(vg)

        -- 描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, bw, btnH, 6)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(btn.color.r, btn.color.g, btn.color.b, 0.55 * alpha))
        nvgStroke(vg)

        -- 文字
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(btn.color.r, btn.color.g, btn.color.b, 0.85 * alpha))
        nvgText(vg, logW * 0.5, by + btnH * 0.5, btn.text)

        -- 存储按钮区域
        table.insert(self.buttons, {
            x = bx, y = by, w = bw, h = btnH, screen = btn.screen
        })
    end

    -- 底部统计
    local statY = logH * 0.92
    local bestiaryCount = GameState.getBestiaryCount()
    local totalExplorations = GameState.data.totalExplorations or 0
    local statText = string.format("图鉴 %d/10 · 探索 %d次", bestiaryCount, totalExplorations)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
        0.55 * alpha))
    nvgText(vg, logW * 0.5, statY, statText)
end

--- 远景水墨山景
function LobbyScreen:drawMountains(vg, logW, logH, t, alpha)
    local ink = InkPalette.inkWash

    -- 远山（淡墨）
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, logH)
    nvgBezierTo(vg,
        logW * 0.2, logH * 0.55 + math.sin(t * 0.3) * 3,
        logW * 0.4, logH * 0.45,
        logW * 0.55, logH * 0.50 + math.sin(t * 0.2 + 1) * 2)
    nvgBezierTo(vg,
        logW * 0.7, logH * 0.48,
        logW * 0.85, logH * 0.52,
        logW, logH * 0.60)
    nvgLineTo(vg, logW, logH)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.08 * alpha))
    nvgFill(vg)

    -- 近山（稍浓）
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, logH)
    nvgBezierTo(vg,
        logW * 0.15, logH * 0.65,
        logW * 0.35, logH * 0.55,
        logW * 0.5, logH * 0.62)
    nvgBezierTo(vg,
        logW * 0.65, logH * 0.58,
        logW * 0.8, logH * 0.65,
        logW, logH * 0.70)
    nvgLineTo(vg, logW, logH)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.12 * alpha))
    nvgFill(vg)

    nvgRestore(vg)
end

--- 资源栏
function LobbyScreen:drawResources(vg, logW, y, alpha)
    local resources = {
        { name = "灵石", value = GameState.getResource("lingshi"), color = InkPalette.jade },
        { name = "兽魂", value = GameState.getResource("shouhun"), color = InkPalette.azure },
        { name = "天晶", value = GameState.getResource("tianjing"), color = InkPalette.gold },
    }

    local totalW = #resources * 80
    local startX = (logW - totalW) * 0.5

    for i, res in ipairs(resources) do
        local rx = startX + (i - 1) * 80

        -- 色标圆
        nvgBeginPath(vg)
        nvgCircle(vg, rx + 8, y, 4)
        nvgFillColor(vg, nvgRGBAf(res.color.r, res.color.g, res.color.b, 0.65 * alpha))
        nvgFill(vg)

        -- 资源名
        nvgFontSize(vg, 12)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.70 * alpha))
        nvgText(vg, rx + 16, y, res.name)

        -- 数值
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
            0.80 * alpha))
        nvgText(vg, rx + 44, y, tostring(res.value))
    end
end

function LobbyScreen:onInput(action, sx, sy)
    if action ~= "tap" then return false end

    for _, btn in ipairs(self.buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then
            if btn.screen == "prepare" then
                local PrepareScreen = require("screens.PrepareScreen")
                ScreenManager.switch(PrepareScreen)
            elseif btn.screen == "book" then
                local BookScreen = require("screens.BookScreen")
                ScreenManager.switch(BookScreen)
            elseif btn.screen == "craft" then
                local CraftScreen = require("screens.CraftScreen")
                ScreenManager.switch(CraftScreen)
            elseif btn.screen == "daily" then
                local DailyScreen = require("screens.DailyScreen")
                ScreenManager.switch(DailyScreen)
            end
            return true
        end
    end
    return false
end

return LobbyScreen
