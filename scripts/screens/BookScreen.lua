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
    -- 卡片点击区域追踪
    self.cardHitAreas = {}
    -- 详情页状态
    self.detailBeast = nil   -- 当前查看的异兽
    self.detailEntry = nil   -- 对应bestiary条目
    self.detailAlpha = 0
    self.detailScrollY = 0
    self.detailMaxScrollY = 0
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
    -- 详情页淡入淡出
    if self.detailBeast then
        self.detailAlpha = math.min(1, self.detailAlpha + dt * 2.5)
    else
        if self.detailAlpha > 0 then
            self.detailAlpha = math.max(0, self.detailAlpha - dt * 3.0)
        end
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

    -- 重置卡片点击区域
    self.cardHitAreas = {}

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
            -- 记录已收录卡片的点击区域（有 lore 的）
            if state == "collected" and beast.lore then
                table.insert(self.cardHitAreas, {
                    x = cardX, y = cy, w = cardW, h = cardH,
                    beast = beast, entry = entry,
                })
            end
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

    -- 详情页叠层
    if self.detailAlpha > 0.01 then
        self:renderDetail(vg, logW, logH, t)
    end
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
    -- 详情页打开时拦截所有输入
    if self.detailBeast then
        if action == "tap" then
            -- 点击关闭详情页
            self.detailBeast = nil
            self.detailEntry = nil
            self.detailScrollY = 0
        elseif action == "drag_y" then
            self.detailScrollY = math.max(0, math.min(self.detailMaxScrollY, self.detailScrollY - sy))
        end
        return true
    end

    if action == "tap" then
        -- 返回按钮
        if self.backBtn then
            if sx >= self.backBtn.x and sx <= self.backBtn.x + self.backBtn.w
               and sy >= self.backBtn.y and sy <= self.backBtn.y + self.backBtn.h then
                local LobbyScreen = require("screens.LobbyScreen")
                ScreenManager.switch(LobbyScreen)
                return true
            end
        end
        -- 卡片点击 → 打开百灵志详情
        for _, area in ipairs(self.cardHitAreas) do
            if sx >= area.x and sx <= area.x + area.w
               and sy >= area.y and sy <= area.y + area.h then
                self.detailBeast = area.beast
                self.detailEntry = area.entry
                self.detailAlpha = 0
                self.detailScrollY = 0
                self.detailMaxScrollY = 0
                return true
            end
        end
    elseif action == "drag_y" then
        self.scrollY = math.max(0, math.min(self.maxScrollY, self.scrollY - sy))
        return true
    end
    return false
end

------------------------------------------------------------
-- 百灵志详情页叠层
------------------------------------------------------------

--- 根据捕获次数计算 lore 文本显示比例
local function getLoreRevealRatio(captureCount)
    if captureCount >= 10 then return 1.0 end
    if captureCount >= 3  then return 0.6 end
    if captureCount >= 1  then return 0.3 end
    return 0
end

function BookScreen:renderDetail(vg, logW, logH, t)
    local P = InkPalette
    local alpha = self.detailAlpha
    local beast = self.detailBeast
    local entry = self.detailEntry

    -- 关闭后淡出期间 beast 可能为 nil
    if not beast then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.55 * alpha))
    nvgFill(vg)

    -- 卡片尺寸
    local cardW = math.min(logW * 0.88, 340)
    local cardH = logH * 0.75
    local cardX = (logW - cardW) * 0.5
    local cardY = (logH - cardH) * 0.5

    -- 卡片底色
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.96 * alpha))
    nvgFill(vg)
    BrushStrokes.inkRect(vg, cardX, cardY, cardW, cardH, P.inkMedium, 0.40 * alpha, 55)

    -- 裁剪到卡片内部
    nvgSave(vg)
    nvgScissor(vg, cardX, cardY, cardW, cardH)

    local contentY = cardY + 24 - self.detailScrollY

    -- 属性标签 + 名称
    local elemColor = ELEM_COLORS[beast.element] or P.inkMedium
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(elemColor.r, elemColor.g, elemColor.b, 0.70 * alpha))
    nvgText(vg, cardX + 20, contentY, beast.element)

    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.90 * alpha))
    nvgText(vg, cardX + 50, contentY, beast.name)

    -- 捕获次数
    local captureCount = entry and entry.count or 0
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
    nvgText(vg, cardX + cardW - 20, contentY, string.format("捕获 %d 次", captureCount))

    -- 分隔线
    contentY = contentY + 26
    BrushStrokes.inkLine(vg, cardX + 20, contentY, cardX + cardW - 20, contentY,
        1.0, P.inkWash, 0.30 * alpha, 44)

    -- 短描述
    contentY = contentY + 16
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.65 * alpha))
    local desc = beast.desc or ""
    nvgTextBox(vg, cardX + 20, contentY, cardW - 40, desc)
    local descBounds = {}
    nvgTextBoxBounds(vg, cardX + 20, contentY, cardW - 40, desc, descBounds)
    contentY = (descBounds[4] or (contentY + 18)) + 16

    -- 百灵志标题
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.75 * alpha))
    nvgText(vg, cardX + 20, contentY, "百灵志")
    contentY = contentY + 24

    -- Lore 文本（根据捕获次数部分解锁）
    local loreText = beast.lore or ""
    local revealRatio = getLoreRevealRatio(captureCount)

    if revealRatio <= 0 then
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50 * alpha))
        nvgTextBox(vg, cardX + 20, contentY, cardW - 40, "尚未捕获此灵兽，无法阅读手记。")
        contentY = contentY + 40
    else
        -- 计算显示的字符数
        -- UTF-8 中文每个字约 3 字节，用 utf8.len 安全处理
        local totalLen = utf8.len(loreText) or #loreText
        local showLen = math.floor(totalLen * revealRatio)
        local revealedText = ""
        local charIdx = 0
        for _, code in utf8.codes(loreText) do
            charIdx = charIdx + 1
            if charIdx > showLen then break end
            revealedText = revealedText .. utf8.char(code)
        end

        -- 显示已解锁文本
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.80 * alpha))
        local loreBounds = {}
        nvgTextBoxBounds(vg, cardX + 20, contentY, cardW - 40, revealedText, loreBounds)
        nvgTextBox(vg, cardX + 20, contentY, cardW - 40, revealedText)
        contentY = (loreBounds[4] or (contentY + 20)) + 8

        -- 未解锁部分用省略号 + 提示
        if revealRatio < 1.0 then
            nvgFontSize(vg, 13)
            nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.50 * alpha))
            nvgTextBox(vg, cardX + 20, contentY, cardW - 40, "……（手记模糊，需更多捕获经验解读）")
            contentY = contentY + 24

            -- 解锁进度提示
            local nextThreshold = captureCount < 3 and 3 or 10
            local pctNow = math.floor(revealRatio * 100)
            local pctNext = captureCount < 3 and 60 or 100
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.55 * alpha))
            nvgText(vg, cardX + 20, contentY,
                string.format("已解读 %d%% · 捕获 %d 次可解读 %d%%", pctNow, nextThreshold, pctNext))
            contentY = contentY + 20
        end
    end

    -- 计算滚动范围
    local contentBottom = contentY + self.detailScrollY + 20
    self.detailMaxScrollY = math.max(0, contentBottom - cardY - cardH)

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 底部关闭提示（在裁剪外）
    local tipAlpha = (0.4 + math.sin(t * 2) * 0.15) * alpha
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, tipAlpha))
    nvgText(vg, logW * 0.5, cardY + cardH - 10, "点击任意处关闭")
end

return BookScreen
