--- ResultScreen - 结算卷轴
--- 卷轴展开动画 + 逐条渐显 + 评分
local InkPalette = require("data.InkPalette")
local GameState = require("systems.GameState")
local ScreenManager = require("systems.ScreenManager")
local BrushStrokes = require("render.BrushStrokes")
local InkRenderer = require("render.InkRenderer")

local ResultScreen = {}
ResultScreen.__index = ResultScreen

function ResultScreen.new(params)
    local self = setmetatable({}, ResultScreen)
    self.isModal = false
    self.contracts = params.contracts or {}
    self.lostContracts = params.lostContracts or {}
    self.resources = params.resources or {}
    self.stats = params.stats or {}
    self.elapsed = params.elapsed or 0

    -- 动画状态
    self.animTime = 0
    self.scrollProgress = 0   -- 卷轴展开 0→1
    self.itemRevealIdx = 0    -- 已揭示条目数
    self.canClose = false
    self.score = 0
    self.settled = false

    return self
end

function ResultScreen:onEnter()
    -- 计算评分
    self:calculateScore()
    -- 结算
    if not self.settled then
        self.settled = true
        GameState.settleSession(self.contracts, self.resources, self.lostContracts)
        GameState.save()
    end
end

function ResultScreen:onExit()
end

function ResultScreen:calculateScore()
    local score = 0
    for _, c in ipairs(self.contracts) do
        local qs = ({ R = 100, SR = 300, SSR = 1000 })[c.quality] or 50
        score = score + qs
    end
    score = score + (self.resources.lingshi or 0) * 2
    score = score + (self.resources.shouhun or 0) * 10
    score = score + (self.resources.tianjing or 0) * 50
    -- 时间奖励
    local timeBonus = math.max(0, math.floor((480 - self.elapsed) / 60) * 50)
    score = score + timeBonus
    -- 丢失扣分
    for _, c in ipairs(self.lostContracts) do
        local penalty = ({ R = 50, SR = 200, SSR = 500 })[c.quality] or 50
        score = score - penalty
    end
    self.score = math.max(0, score)
end

function ResultScreen:update(dt)
    self.animTime = self.animTime + dt

    -- 卷轴展开 (0 ~ 1.0s)
    if self.scrollProgress < 1 then
        self.scrollProgress = math.min(1, self.scrollProgress + dt * 1.2)
    end

    -- 逐条揭示 (展开后)
    if self.scrollProgress >= 1 then
        local totalItems = #self.contracts + #self.lostContracts + 3 -- +标题行+时间+评分
        local revealSpeed = 2.0
        self.itemRevealIdx = math.min(totalItems, self.itemRevealIdx + dt * revealSpeed)
    end

    -- 1.5s 后可关闭
    if self.animTime > 1.5 then
        self.canClose = true
    end
end

function ResultScreen:onInput(action, sx, sy)
    if action == "down" and self.canClose then
        local LobbyScreen = require("screens.LobbyScreen")
        ScreenManager.switch(LobbyScreen)
        return true
    end
    return true
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function ResultScreen:render(vg, logW, logH, t)
    local P = InkPalette

    -- 宣纸底
    InkRenderer.drawPaperBase(vg, logW, logH, t)

    -- 卷轴
    local scrollW = math.min(logW * 0.85, 360)
    local maxScrollH = logH * 0.78
    local scrollX = (logW - scrollW) * 0.5
    local scrollCY = logH * 0.48

    -- 展开动画：从中心线向上下扩展
    local halfH = maxScrollH * 0.5 * self:easeOutQuad(self.scrollProgress)
    local scrollY = scrollCY - halfH
    local scrollH = halfH * 2

    if scrollH < 2 then
        nvgRestore(vg)
        return
    end

    nvgSave(vg)

    -- 卷轴底纹
    nvgBeginPath(vg)
    nvgRoundedRect(vg, scrollX, scrollY, scrollW, scrollH, 4)
    nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.95))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 裁剪到卷轴内部
    nvgScissor(vg, scrollX, scrollY, scrollW, scrollH)

    if self.scrollProgress >= 1 then
        self:renderContent(vg, scrollX, scrollY, scrollW, scrollH, t)
    end

    nvgResetScissor(vg)
    nvgRestore(vg)

    -- 底部提示
    if self.canClose then
        local tipAlpha = 0.3 + math.sin(t * 2) * 0.15
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, tipAlpha))
        nvgText(vg, logW * 0.5, logH * 0.95, "点击任意处返回")
    end
end

------------------------------------------------------------
-- 卷轴内容
------------------------------------------------------------

function ResultScreen:renderContent(vg, sx, sy, sw, sh, t)
    local P = InkPalette
    local cx = sx + sw * 0.5
    local curY = sy + 24
    local revealIdx = math.floor(self.itemRevealIdx)
    local itemIdx = 0

    -- 标题
    itemIdx = itemIdx + 1
    if revealIdx >= itemIdx then
        local alpha = math.min(1, (self.itemRevealIdx - itemIdx + 1))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, alpha * 0.9))
        nvgText(vg, cx, curY, "寻光录·结算")
        curY = curY + 36

        -- 装饰线
        BrushStrokes.inkLine(vg, cx - 60, curY, cx + 60, curY, 1, P.inkWash, alpha * 0.4, 42)
        curY = curY + 16
    else
        return
    end

    -- 获得灵契
    if #self.contracts > 0 then
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
        nvgText(vg, sx + 20, curY, "获得灵契")
        curY = curY + 22

        for _, contract in ipairs(self.contracts) do
            itemIdx = itemIdx + 1
            if revealIdx >= itemIdx then
                local alpha = math.min(1, (self.itemRevealIdx - itemIdx + 1))
                local qualColor = P.qualColor(contract.quality)

                -- 品质标签
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBAf(qualColor.r, qualColor.g, qualColor.b, alpha * 0.8))
                nvgText(vg, sx + 30, curY, "[" .. contract.quality .. "]")

                -- 名字
                nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, alpha * 0.8))
                nvgText(vg, sx + 75, curY, contract.name)

                -- SSR 墨点装饰
                if contract.quality == "SSR" then
                    BrushStrokes.inkDotStable(vg, sx + sw - 30, curY + 7, 5, P.gold, alpha * 0.6, 77)
                end

                curY = curY + 24
            end
        end
        curY = curY + 8
    end

    -- 灵契破碎
    if #self.lostContracts > 0 then
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.7))
        nvgText(vg, sx + 20, curY, "灵契破碎")
        curY = curY + 22

        for _, contract in ipairs(self.lostContracts) do
            itemIdx = itemIdx + 1
            if revealIdx >= itemIdx then
                local alpha = math.min(1, (self.itemRevealIdx - itemIdx + 1))
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, alpha * 0.6))
                nvgText(vg, sx + 30, curY, "[" .. contract.quality .. "] " .. contract.name .. " 散逸")
                curY = curY + 24
            end
        end
        curY = curY + 8
    end

    -- 探索时长
    itemIdx = itemIdx + 1
    if revealIdx >= itemIdx then
        local alpha = math.min(1, (self.itemRevealIdx - itemIdx + 1))
        local minutes = math.floor(self.elapsed / 60)
        local seconds = math.floor(self.elapsed % 60)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, alpha * 0.7))
        nvgText(vg, cx, curY, string.format("探索时长: %dm %ds", minutes, seconds))
        curY = curY + 24
    end

    -- 评分
    itemIdx = itemIdx + 1
    if revealIdx >= itemIdx then
        local alpha = math.min(1, (self.itemRevealIdx - itemIdx + 1))
        curY = curY + 8
        nvgFontSize(vg, 26)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, alpha * 0.9))
        nvgText(vg, cx, curY, tostring(self.score))
    end
end

function ResultScreen:easeOutQuad(x)
    return 1 - (1 - x) * (1 - x)
end

return ResultScreen
