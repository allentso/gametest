--- 灵兽图鉴屏 - v2: 品质分层展示
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local BeastData = require("data.BeastData")

local BookScreen = {}
BookScreen.__index = BookScreen

-- 属性→颜色映射
local ELEM_COLORS = {
    ["火"] = { r = 0.76, g = 0.23, b = 0.18 },
    ["水"] = { r = 0.35, g = 0.55, b = 0.72 },
    ["雷"] = { r = 0.70, g = 0.60, b = 0.15 },
    ["光"] = { r = 0.80, g = 0.68, b = 0.20 },
    ["暗"] = { r = 0.30, g = 0.20, b = 0.35 },
    ["土"] = { r = 0.60, g = 0.50, b = 0.35 },
    ["风"] = { r = 0.30, g = 0.58, b = 0.45 },
    ["冰"] = { r = 0.50, g = 0.72, b = 0.80 },
}

-- 品质标签配置
local QUAL_LABELS = {
    { key = "R",   label = "普通" },
    { key = "SR",  label = "异色" },
    { key = "SSR", label = "闪光" },
}

function BookScreen.new(params)
    local self = setmetatable({}, BookScreen)
    self.fadeIn = 0
    self.t = 0
    self.scrollY = 0
    self.maxScrollY = 0
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
    local P = InkPalette

    -- 宣纸底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 1.0))
    nvgFill(vg)

    -- 标题栏
    nvgFontSize(vg, 22)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.05, "灵兽图鉴")

    -- 返回
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.65 * alpha))
    nvgText(vg, 16, logH * 0.05, "< 返回")
    self.backBtn = { x = 0, y = logH * 0.02, w = 80, h = 30 }

    -- 收录进度：统计已收录灵兽数 + 总品质收集数
    local collectedBeasts = GameState.getBestiaryCount()
    local totalBeasts = #BeastData
    local totalQualities = 0
    local collectedQualities = 0
    for _, beast in ipairs(BeastData) do
        totalQualities = totalQualities + 3  -- R/SR/SSR
        local entry = GameState.data.bestiary[beast.id]
        if entry and entry.qualities then
            for _, q in ipairs(QUAL_LABELS) do
                if (entry.qualities[q.key] or 0) > 0 then
                    collectedQualities = collectedQualities + 1
                end
            end
        end
    end

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.60 * alpha))
    nvgText(vg, logW - 16, logH * 0.05,
        string.format("收录 %d/%d", collectedBeasts, totalBeasts))

    -- 品质进度条（标题下方）
    local progY = logH * 0.075
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.45 * alpha))
    nvgText(vg, logW * 0.5, progY,
        string.format("品质完成度 %d/%d", collectedQualities, totalQualities))

    -- 分隔线
    BrushStrokes.inkLine(vg, logW * 0.1, logH * 0.09, logW * 0.9, logH * 0.09,
        1.0, P.inkWash, 0.20 * alpha, 77)

    -- 卡片列表
    local cardW = logW * 0.88
    local cardX = (logW - cardW) * 0.5
    local startY = logH * 0.10 - self.scrollY
    local cardGap = 12

    -- 裁剪区域（标题栏以下）
    nvgSave(vg)
    nvgScissor(vg, 0, logH * 0.09, logW, logH * 0.91)

    for i, beast in ipairs(BeastData) do
        local entry = GameState.data.bestiary[beast.id]
        local state = "undiscovered"
        if entry then
            state = entry.captured and "collected" or "encountered"
        end

        -- 根据状态决定卡片高度
        local cardH
        if state == "collected" then
            cardH = logH * 0.16  -- 更高，容纳品质槽位
        else
            cardH = logH * 0.10
        end

        local cy = startY + self:getCardOffset(i, startY, logH)

        -- 跳过不可见卡片
        if cy + cardH >= 0 and cy <= logH then
            self:renderCard(vg, cardX, cy, cardW, cardH, beast, entry, state, alpha, t)
        end

        -- 累计偏移给下一张卡片
        if i == 1 then
            self["_cardOffsets"] = { [1] = 0 }
        end
    end

    -- 计算最大滚动距离
    local totalH = self:getTotalHeight(logH)
    self.maxScrollY = math.max(0, totalH - logH * 0.88)

    nvgResetScissor(vg)
    nvgRestore(vg)
end

--- 计算第 i 张卡片的 Y 偏移
function BookScreen:getCardOffset(idx, startY, logH)
    local y = 0
    local cardGap = 12
    for i = 1, idx - 1 do
        local beast = BeastData[i]
        local entry = GameState.data.bestiary[beast.id]
        local state = "undiscovered"
        if entry then
            state = entry.captured and "collected" or "encountered"
        end
        local cardH = (state == "collected") and (logH * 0.16) or (logH * 0.10)
        y = y + cardH + cardGap
    end
    return y
end

--- 计算总内容高度
function BookScreen:getTotalHeight(logH)
    local total = 0
    local cardGap = 12
    for i, beast in ipairs(BeastData) do
        local entry = GameState.data.bestiary[beast.id]
        local state = "undiscovered"
        if entry then
            state = entry.captured and "collected" or "encountered"
        end
        local cardH = (state == "collected") and (logH * 0.16) or (logH * 0.10)
        total = total + cardH + cardGap
    end
    return total
end

------------------------------------------------------------
-- 单张卡片渲染
------------------------------------------------------------

function BookScreen:renderCard(vg, x, y, w, h, beast, entry, state, alpha, t)
    local P = InkPalette

    -- 判断是否三品质全集
    local allCollected = false
    if entry and entry.qualities then
        allCollected = (entry.qualities.R or 0) > 0
            and (entry.qualities.SR or 0) > 0
            and (entry.qualities.SSR or 0) > 0
    end

    -- 卡片底色
    local bgColor, bgAlpha
    if allCollected then
        bgColor = P.gold
        bgAlpha = 0.10
    elseif state == "collected" then
        bgColor = P.gold
        bgAlpha = 0.05
    elseif state == "encountered" then
        bgColor = P.inkWash
        bgAlpha = 0.06
    else
        bgColor = P.inkLight
        bgAlpha = 0.04
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 6)
    nvgFillColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, bgAlpha * alpha))
    nvgFill(vg)

    -- 边框
    local borderColor, borderAlpha
    if allCollected then
        -- 描金边框 + 微光
        borderColor = P.gold
        borderAlpha = 0.50 + math.sin(t * 1.5) * 0.10
    else
        borderColor = bgColor
        borderAlpha = 0.20
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 6)
    nvgStrokeWidth(vg, allCollected and 1.2 or 0.8)
    nvgStrokeColor(vg, nvgRGBAf(borderColor.r, borderColor.g, borderColor.b, borderAlpha * alpha))
    nvgStroke(vg)

    -- ---- 未发现 ----
    if state == "undiscovered" then
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40 * alpha))
        nvgText(vg, x + w * 0.5, y + h * 0.5, "???")
        return
    end

    -- ---- 见闻（遭遇过但未捕获） ----
    if state == "encountered" then
        -- 属性标签
        local elemColor = ELEM_COLORS[beast.element] or P.inkMedium
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(elemColor.r, elemColor.g, elemColor.b, 0.40 * alpha))
        nvgText(vg, x + 12, y + h * 0.35, beast.element)

        -- 名称（半透明）
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.45 * alpha))
        nvgText(vg, x + 35, y + h * 0.35, beast.name)

        -- 提示
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.35 * alpha))
        nvgText(vg, x + 12, y + h * 0.70, "曾见其踪，尚未封灵")
        return
    end

    -- ---- 已收录 ----

    -- 第一行：属性标签 + 名称 + 总捕获次数
    local row1Y = y + h * 0.18

    -- 属性小标签
    local elemColor = ELEM_COLORS[beast.element] or P.inkMedium
    local elemLabelW = 24
    local elemLabelH = 14
    local elemLabelX = x + 10
    local elemLabelY = row1Y - elemLabelH * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, elemLabelX, elemLabelY, elemLabelW, elemLabelH, 2)
    nvgFillColor(vg, nvgRGBAf(elemColor.r, elemColor.g, elemColor.b, 0.12 * alpha))
    nvgFill(vg)

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(elemColor.r, elemColor.g, elemColor.b, 0.70 * alpha))
    nvgText(vg, elemLabelX + elemLabelW * 0.5, row1Y, beast.element)

    -- 名称
    nvgFontSize(vg, 17)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, x + 40, row1Y, beast.name)

    -- 总捕获次数
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
    nvgText(vg, x + w - 12, row1Y,
        string.format("共捕获 %d 次", entry.count or 0))

    -- 第二行：百灵志短描述
    local row2Y = y + h * 0.40
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.45 * alpha))
    local desc = beast.desc or "追踪异兽之踪迹，以灵符封印"
    nvgText(vg, x + 12, row2Y, desc)

    -- 百灵志标记（有 lore 数据时显示"百灵志 ▸"提示）
    if beast.lore then
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.40 * alpha))
        nvgText(vg, x + w - 12, row2Y, "百灵志 ▸")
    end

    -- 分隔细线
    local sepY = y + h * 0.55
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 12, sepY)
    nvgLineTo(vg, x + w - 12, sepY)
    nvgStrokeWidth(vg, 0.5)
    nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.30 * alpha))
    nvgStroke(vg)

    -- 第三行：品质槽位 R / SR / SSR
    local row3Y = y + h * 0.73
    local slotW = (w - 36) / 3
    local qualities = entry.qualities or { R = 0, SR = 0, SSR = 0 }

    for qi, qInfo in ipairs(QUAL_LABELS) do
        local slotX = x + 12 + (qi - 1) * (slotW + 6)
        local slotCX = slotX + slotW * 0.5
        local qCount = qualities[qInfo.key] or 0
        local qColor = P.qualColor(qInfo.key)
        local hasThis = qCount > 0

        -- 品质墨点
        local dotR = 5
        if hasThis then
            -- 实心墨点（已获得）
            BrushStrokes.inkDotStable(vg, slotCX - 20, row3Y, dotR,
                qColor, 0.75 * alpha, qi * 31 + 7)
        else
            -- 空心圆（未获得）
            nvgBeginPath(vg)
            nvgCircle(vg, slotCX - 20, row3Y, dotR)
            nvgStrokeWidth(vg, 0.8)
            nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35 * alpha))
            nvgStroke(vg)
        end

        -- 品质名称
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if hasThis then
            nvgFillColor(vg, nvgRGBAf(qColor.r, qColor.g, qColor.b, 0.75 * alpha))
        else
            nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40 * alpha))
        end
        nvgText(vg, slotCX - 12, row3Y, qInfo.key)

        -- 捕获次数
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if hasThis then
            nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
            nvgText(vg, slotCX + 10, row3Y, string.format("×%d", qCount))
        else
            nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.30 * alpha))
            nvgText(vg, slotCX + 10, row3Y, "×0")
        end

        -- 品质中文标签（在次数下方）
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if hasThis then
            nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.40 * alpha))
        else
            nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.25 * alpha))
        end
        nvgText(vg, slotCX, row3Y + 14, qInfo.label)
    end

    -- 全品质集齐标记
    if allCollected then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b,
            (0.65 + math.sin(t * 2) * 0.15) * alpha))
        nvgText(vg, x + w - 12, row3Y, "全品质")
    end
end

------------------------------------------------------------
-- 输入处理
------------------------------------------------------------

function BookScreen:onInput(action, sx, sy)
    if action == "tap" and self.backBtn then
        if sx >= self.backBtn.x and sx <= self.backBtn.x + self.backBtn.w
           and sy >= self.backBtn.y and sy <= self.backBtn.y + self.backBtn.h then
            local LobbyScreen = require("screens.LobbyScreen")
            ScreenManager.switch(LobbyScreen)
            return true
        end
    elseif action == "drag_y" then
        self.scrollY = math.max(0, math.min(self.maxScrollY, self.scrollY - sy))
        return true
    end
    return false
end

return BookScreen
