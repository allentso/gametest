--- PrepareScreen - 三步出发准备：选灵境→选流派→配道具
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local BeastData = require("data.BeastData")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local SessionState = require("systems.SessionState")

local PrepareScreen = {}
PrepareScreen.__index = PrepareScreen

local BIOMES = {
    { id = "翠谷灵境", beasts = "石灵·土偶·风鸣·水蛟·冰蚕", trait = "竹林最多，隐蔽战术", unlockLevel = 1 },
    { id = "雷峰灵境", beasts = "雷翼·白泽·风鸣",           trait = "无水面，瘴气偏高",   unlockLevel = 2 },
    { id = "焰渊灵境", beasts = "玄狐·墨鸦·石灵",           trait = "天晶×1.5，瘴气加倍", unlockLevel = 2 },
    { id = "幽潭灵境", beasts = "水蛟·冰蚕·噬天",           trait = "水面最多，水蛟难追",  unlockLevel = 3 },
    { id = "虚空灵境", beasts = "全部10种",                  trait = "收缩×1.2，SSR+5%",   unlockLevel = 5 },
}

local SCHOOLS = {
    { id = "trace",    name = "追迹流", desc = "快速收集线索触发SSR", color = nil },
    { id = "suppress", name = "压制流", desc = "强化QTE表现",        color = nil },
    { id = "evac",     name = "撤离流", desc = "强化撤离安全性",     color = nil },
    { id = "greed",    name = "贪渊流", desc = "高危区高收益",        color = nil, unlockLevel = 4 },
}

local ITEMS = {
    { id = "sealer_t2", name = "青玉壶",   category = "sealer", desc = "封印成功率85%", usage = "压制后选用" },
    { id = "sealer_t3", name = "金缕珠",   category = "sealer", desc = "封印成功率92%", usage = "压制后选用" },
    { id = "sealer_t4", name = "天命盘",   category = "sealer", desc = "封印成功率98%", usage = "压制后选用" },
    { id = "sealer_t5", name = "混沌印",   category = "sealer", desc = "封印成功率100%", usage = "压制后选用" },
    { id = "rushWard",  name = "疾风符",   category = "item",   desc = "移速+30%，持续60秒", usage = "点击激活" },
    { id = "fogMap",    name = "迷雾残图", category = "item",   desc = "开局揭示25%地图", usage = "自动生效" },
    { id = "beastEye",  name = "兽目珠",   category = "item",   desc = "显示异兽位置15秒", usage = "点击激活" },
    { id = "sealEcho",  name = "封印回响", category = "item",   desc = "压制失败可重试1次", usage = "自动生效" },
}

function PrepareScreen.new(params)
    local self = setmetatable({}, PrepareScreen)
    self.fadeIn = 0
    self.t = 0
    self.step = 1
    self.selectedBiome = nil
    self.selectedSchool = nil
    self.selectedItems = {}
    self.buttons = {}
    return self
end

function PrepareScreen:onEnter()
    self.fadeIn = 0
    self.step = 1
    self.selectedBiome = nil
    self.selectedSchool = nil
    self.selectedItems = {}
    for _, item in ipairs(ITEMS) do
        self.selectedItems[item.id] = 0
    end
end

function PrepareScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
end

function PrepareScreen:render(vg, logW, logH, t)
    local alpha = self.fadeIn
    local P = InkPalette

    -- 宣纸底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 1.0))
    nvgFill(vg)

    self.buttons = {}

    -- 步骤指示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local stepLabels = { "选择灵境", "选择流派", "配置道具" }
    for i = 1, 3 do
        local sx = logW * (0.2 + (i - 1) * 0.3)
        local c = (i == self.step) and P.cinnabar or P.inkWash
        local a = (i == self.step) and 0.85 or 0.4
        nvgFillColor(vg, nvgRGBAf(c.r, c.g, c.b, a * alpha))
        nvgText(vg, sx, logH * 0.03, stepLabels[i])
    end

    -- 返回按钮
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.65 * alpha))
    nvgText(vg, 16, logH * 0.06, "< 返回")
    table.insert(self.buttons, { type = "back", x = 0, y = logH * 0.03, w = 80, h = 30 })

    if self.step == 1 then
        self:renderBiomeSelect(vg, logW, logH, alpha)
    elseif self.step == 2 then
        self:renderSchoolSelect(vg, logW, logH, alpha)
    elseif self.step == 3 then
        self:renderItemSelect(vg, logW, logH, alpha)
    end
end

------------------------------------------------------------
-- Step 1: 灵境选择
------------------------------------------------------------

function PrepareScreen:renderBiomeSelect(vg, logW, logH, alpha)
    local P = InkPalette
    local level = GameState.getSealerLevel()

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.10, "选择灵境")

    local cardW = logW * 0.85
    local cardH = logH * 0.12
    local startY = logH * 0.16
    local gap = 8

    for i, biome in ipairs(BIOMES) do
        local cy = startY + (i - 1) * (cardH + gap)
        local unlocked = level >= biome.unlockLevel
        local selected = self.selectedBiome == biome.id
        local bgAlpha = selected and 0.15 or 0.05

        -- 卡片
        nvgBeginPath(vg)
        nvgRoundedRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, 6)
        local bgColor = selected and P.cinnabar or P.jade
        nvgFillColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, bgAlpha * alpha))
        nvgFill(vg)

        if selected then
            BrushStrokes.inkRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, P.cinnabar, 0.5, i * 17)
        end

        local textAlpha = unlocked and 0.85 or 0.3

        -- 灵境名
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, textAlpha * alpha))
        nvgText(vg, (logW - cardW) * 0.5 + 14, cy + cardH * 0.3,
            unlocked and biome.id or (biome.id .. " (境界" .. biome.unlockLevel .. ")"))

        -- 异兽种类
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, textAlpha * 0.7 * alpha))
        nvgText(vg, (logW - cardW) * 0.5 + 14, cy + cardH * 0.6, biome.beasts)

        -- 特色
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, textAlpha * 0.6 * alpha))
        nvgText(vg, (logW + cardW) * 0.5 - 14, cy + cardH * 0.6, biome.trait)

        if unlocked then
            table.insert(self.buttons, {
                type = "biome", biomeId = biome.id,
                x = (logW - cardW) * 0.5, y = cy, w = cardW, h = cardH,
            })
        end
    end

    -- 下一步按钮
    if self.selectedBiome then
        self:renderNextButton(vg, logW, logH, alpha, "选择流派 >")
    end
end

------------------------------------------------------------
-- Step 2: 流派选择
------------------------------------------------------------

function PrepareScreen:renderSchoolSelect(vg, logW, logH, alpha)
    local P = InkPalette
    local level = GameState.getSealerLevel()

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.10, "选择封印流派")

    local cardW = logW * 0.85
    local cardH = logH * 0.14
    local startY = logH * 0.18
    local gap = 10

    for i, school in ipairs(SCHOOLS) do
        local cy = startY + (i - 1) * (cardH + gap)
        local unlocked = not school.unlockLevel or level >= school.unlockLevel
        local selected = self.selectedSchool == school.id

        nvgBeginPath(vg)
        nvgRoundedRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, 6)
        local bgColor = selected and P.cinnabar or P.jade
        nvgFillColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, (selected and 0.15 or 0.05) * alpha))
        nvgFill(vg)

        if selected then
            BrushStrokes.inkRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, P.cinnabar, 0.5, i * 23)
        end

        local textAlpha = unlocked and 0.85 or 0.3

        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, textAlpha * alpha))
        nvgText(vg, (logW - cardW) * 0.5 + 14, cy + cardH * 0.35,
            unlocked and school.name or (school.name .. " (境界" .. (school.unlockLevel or 1) .. ")"))

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, textAlpha * 0.7 * alpha))
        nvgText(vg, (logW - cardW) * 0.5 + 14, cy + cardH * 0.7, school.desc)

        if unlocked then
            table.insert(self.buttons, {
                type = "school", schoolId = school.id,
                x = (logW - cardW) * 0.5, y = cy, w = cardW, h = cardH,
            })
        end
    end

    if self.selectedSchool then
        self:renderNextButton(vg, logW, logH, alpha, "配置道具 >")
    end
end

------------------------------------------------------------
-- Step 3: 道具配置
------------------------------------------------------------

function PrepareScreen:renderItemSelect(vg, logW, logH, alpha)
    local P = InkPalette

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.10, "配置道具")

    -- 计算已选道具格数（仅限 category=="item" 的道具）
    local usedSlots = 0
    for _, item in ipairs(ITEMS) do
        if item.category == "item" then
            usedSlots = usedSlots + (self.selectedItems[item.id] or 0)
        end
    end
    local maxSlots = 3

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.6 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.13, "素灵符(免费)×3 已自动装备")
    local slotColor = usedSlots >= maxSlots and P.cinnabar or P.jade
    nvgFillColor(vg, nvgRGBAf(slotColor.r, slotColor.g, slotColor.b, 0.7 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.16, string.format("道具格: %d / %d", usedSlots, maxSlots))

    local cardW = logW * 0.85
    local cardH = 62
    local startY = logH * 0.20
    local gap = 5
    local cardX = (logW - cardW) * 0.5

    for i, item in ipairs(ITEMS) do
        local cy = startY + (i - 1) * (cardH + gap)
        local stock = GameState.getResource(item.id)
        local sel = self.selectedItems[item.id] or 0

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, 4)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.05 * alpha))
        nvgFill(vg)

        -- 名称
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.8 * alpha))
        nvgText(vg, cardX + 12, cy + cardH * 0.28, item.name)

        -- 效果描述
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.6 * alpha))
        nvgText(vg, cardX + 12, cy + cardH * 0.58, item.desc or "")

        -- 使用方式标签
        if item.usage then
            local usageColor = (item.usage == "点击激活") and P.jade or P.azure
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBAf(usageColor.r, usageColor.g, usageColor.b, 0.55 * alpha))
            nvgText(vg, cardX + 12, cy + cardH * 0.82, item.usage)
        end

        -- 库存
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, cardX + cardW * 0.48, cy + cardH * 0.28, "库存:" .. stock)

        -- 已选数量
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
        nvgText(vg, cardX + cardW - 50, cy + cardH * 0.45, tostring(sel))

        -- +/- 按钮
        local btnR = 12
        local minusCX = cardX + cardW - 80
        local plusCX = cardX + cardW - 18
        local btnCY = cy + cardH * 0.45

        nvgBeginPath(vg)
        nvgCircle(vg, minusCX, btnCY, btnR)
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.4 * alpha))
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.6 * alpha))
        nvgText(vg, minusCX, btnCY, "-")

        nvgBeginPath(vg)
        nvgCircle(vg, plusCX, btnCY, btnR)
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.5 * alpha))
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.7 * alpha))
        nvgText(vg, plusCX, btnCY, "+")

        table.insert(self.buttons, {
            type = "minus", itemId = item.id,
            x = minusCX - btnR, y = btnCY - btnR, w = btnR * 2, h = btnR * 2,
        })
        table.insert(self.buttons, {
            type = "plus", itemId = item.id,
            x = plusCX - btnR, y = btnCY - btnR, w = btnR * 2, h = btnR * 2,
        })
    end

    -- 出发按钮
    local mainBtnW = 180
    local mainBtnH = 44
    local mainBtnX = (logW - mainBtnW) * 0.5
    local mainBtnY = logH * 0.85
    local breathe = 1.0 + math.sin(self.t * 2) * 0.03

    nvgBeginPath(vg)
    nvgRoundedRect(vg, mainBtnX, mainBtnY, mainBtnW * breathe, mainBtnH, 6)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.15 * alpha))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mainBtnX, mainBtnY, mainBtnW * breathe, mainBtnH, 6)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.65 * alpha))
    nvgStroke(vg)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, mainBtnY + mainBtnH * 0.5, "踏入灵境")

    table.insert(self.buttons, {
        type = "enter",
        x = mainBtnX, y = mainBtnY, w = mainBtnW, h = mainBtnH,
    })
end

------------------------------------------------------------
-- 下一步按钮
------------------------------------------------------------

function PrepareScreen:renderNextButton(vg, logW, logH, alpha, label)
    local P = InkPalette
    local btnW = 140
    local btnH = 36
    local btnX = (logW - btnW) * 0.5
    local btnY = logH * 0.88

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 6)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.12 * alpha))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1)
    nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.5 * alpha))
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, btnY + btnH * 0.5, label)

    table.insert(self.buttons, {
        type = "next",
        x = btnX, y = btnY, w = btnW, h = btnH,
    })
end

------------------------------------------------------------
-- 输入
------------------------------------------------------------

function PrepareScreen:onInput(action, sx, sy)
    if action ~= "tap" then return false end

    for _, btn in ipairs(self.buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then

            if btn.type == "biome" then
                self.selectedBiome = btn.biomeId
                return true

            elseif btn.type == "school" then
                self.selectedSchool = btn.schoolId
                return true

            elseif btn.type == "next" then
                self.step = self.step + 1
                return true

            elseif btn.type == "plus" then
                local stock = GameState.getResource(btn.itemId)
                if (self.selectedItems[btn.itemId] or 0) < stock then
                    -- 道具格限制：非封灵器类道具总数不超过3
                    local isItem = false
                    for _, it in ipairs(ITEMS) do
                        if it.id == btn.itemId and it.category == "item" then
                            isItem = true; break
                        end
                    end
                    if isItem then
                        local slots = 0
                        for _, it in ipairs(ITEMS) do
                            if it.category == "item" then
                                slots = slots + (self.selectedItems[it.id] or 0)
                            end
                        end
                        if slots >= 3 then return true end
                    end
                    self.selectedItems[btn.itemId] = (self.selectedItems[btn.itemId] or 0) + 1
                end
                return true

            elseif btn.type == "minus" then
                if (self.selectedItems[btn.itemId] or 0) > 0 then
                    self.selectedItems[btn.itemId] = self.selectedItems[btn.itemId] - 1
                end
                return true

            elseif btn.type == "enter" then
                SessionState.reset()
                SessionState.selectedBiome = self.selectedBiome
                SessionState.selectedSchool = self.selectedSchool

                for id, count in pairs(self.selectedItems) do
                    if count > 0 then
                        GameState.spendResource(id, count)
                        SessionState.addItem(id, count)
                    end
                end

                -- 迷雾残图代价：自带素灵符从3个减少到2个
                if (self.selectedItems["fogMap"] or 0) > 0 then
                    SessionState.inventory.sealer_free = 2
                end

                GameState.save()

                local ExploreScreen = require("screens.ExploreScreen")
                ScreenManager.switch(ExploreScreen)
                return true

            elseif btn.type == "back" then
                if self.step > 1 then
                    self.step = self.step - 1
                else
                    local LobbyScreen = require("screens.LobbyScreen")
                    ScreenManager.switch(LobbyScreen)
                end
                return true
            end
        end
    end
    return false
end

return PrepareScreen
