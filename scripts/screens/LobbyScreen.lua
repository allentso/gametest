--- 大厅屏幕 - 水墨山景 + 四个导航入口
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local InkRenderer = require("render.InkRenderer")
local Config = require("Config")

local LobbyScreen = {}
LobbyScreen.__index = LobbyScreen

function LobbyScreen.new(params)
    local self = setmetatable({}, LobbyScreen)
    self.fadeIn = 0
    self.t = 0
    self.buttons = {}
    -- 里程碑弹出
    self.milestone = nil        -- { title, note, count }
    self.milestoneAlpha = 0
    self.milestoneDismissed = false
    return self
end

function LobbyScreen:onEnter()
    self.fadeIn = 0
    self.t = 0
    -- 检查待展示的里程碑
    if GameState.data.pendingMilestone then
        self.milestone = GameState.data.pendingMilestone
        self.milestoneAlpha = 0
        self.milestoneDismissed = false
        GameState.data.pendingMilestone = nil
        GameState.save()
        print("[LobbyScreen] 发现新里程碑: " .. self.milestone.title)
    end
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
    -- 里程碑弹出淡入淡出
    if self.milestone and not self.milestoneDismissed then
        self.milestoneAlpha = math.min(1, self.milestoneAlpha + dt * 1.5)
    elseif self.milestoneDismissed and self.milestoneAlpha > 0 then
        self.milestoneAlpha = math.max(0, self.milestoneAlpha - dt * 2.0)
        if self.milestoneAlpha <= 0 then
            self.milestone = nil
        end
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
    local sealerLevel = GameState.getSealerLevel()
    local LEVEL_NAMES = { "初入门", "识迹师", "调灵者", "封灵师", "灵契使", "百灵志者", "天命封灵" }
    local levelName = LEVEL_NAMES[sealerLevel] or "初入门"
    local statText = string.format("境界%d·%s | 图鉴 %d/10 | 探索 %d次",
        sealerLevel, levelName, bestiaryCount, totalExplorations)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
        0.55 * alpha))
    nvgText(vg, logW * 0.5, statY, statText)

    -- 里程碑弹出叠加层
    if self.milestone and self.milestoneAlpha > 0.01 then
        self:renderMilestone(vg, logW, logH, t)
    end
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
        { name = "灵印", value = GameState.getResource("lingyin"), color = InkPalette.cinnabar },
    }

    local totalW = #resources * 70
    local startX = (logW - totalW) * 0.5

    for i, res in ipairs(resources) do
        local rx = startX + (i - 1) * 70

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
    -- 里程碑弹出：点击关闭
    if self.milestone and not self.milestoneDismissed and self.milestoneAlpha > 0.5 then
        if action == "down" or action == "tap" then
            self.milestoneDismissed = true
        end
        return true -- 弹出期间拦截所有输入
    end

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

------------------------------------------------------------
-- 里程碑弹出卡片
------------------------------------------------------------
function LobbyScreen:renderMilestone(vg, logW, logH, t)
    local P = InkPalette
    local a = self.milestoneAlpha
    local ms = self.milestone

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.45 * a))
    nvgFill(vg)

    -- 卡片尺寸
    local cardW = math.min(logW * 0.82, 320)
    local cardH = logH * 0.48
    local cardX = (logW - cardW) * 0.5
    local cardY = (logH - cardH) * 0.5

    -- 卡片底
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 6)
    nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.96 * a))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.50 * a))
    nvgStroke(vg)

    nvgScissor(vg, cardX, cardY, cardW, cardH)

    local cx = cardX + cardW * 0.5
    local curY = cardY + 28

    -- 装饰墨点
    BrushStrokes.inkDotStable(vg, cx, curY, 6, P.gold, 0.55 * a, 99)
    curY = curY + 20

    -- "封灵师手记" 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.6 * a))
    nvgText(vg, cx, curY, "— 封灵师手记 —")
    curY = curY + 26

    -- 里程碑标题
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.90 * a))
    nvgText(vg, cx, curY, ms.title)
    curY = curY + 30

    -- 图鉴数提示
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.70 * a))
    nvgText(vg, cx, curY, "图鉴收录达到 " .. ms.count .. " 种")
    curY = curY + 24

    -- 分隔线
    BrushStrokes.inkLine(vg, cx - 50, curY, cx + 50, curY, 1, P.inkWash, 0.3 * a, 55)
    curY = curY + 16

    -- 手记正文（nvgTextBox 自动换行）
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.80 * a))
    local textPad = 24
    local textW = cardW - textPad * 2
    nvgTextBox(vg, cardX + textPad, curY, textW, ms.note)

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 底部提示
    local tipAlpha = (0.3 + math.sin(t * 2) * 0.15) * a
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, tipAlpha))
    nvgText(vg, logW * 0.5, cardY + cardH + 16, "点击任意处继续")
end

return LobbyScreen
