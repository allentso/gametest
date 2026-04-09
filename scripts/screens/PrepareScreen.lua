--- PrepareScreen - 四步出发准备：选灵境→选流派→选技能→配道具
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local BeastData = require("data.BeastData")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local SessionState = require("systems.SessionState")
local SkillSystem = require("systems.SkillSystem")

local PrepareScreen = {}
PrepareScreen.__index = PrepareScreen

local BIOMES = {
    { id = "翠谷灵境", beasts = "兆兽五、异兽四、神灵二，多温驯之属，土水之气盛", trait = "竹林最多，隐蔽战术", unlockLevel = 1 },
    { id = "雷峰灵境", beasts = "兆兽四、异兽三、神灵二，多凶悍之属，雷风之气烈", trait = "无水面，瘴气偏高", unlockLevel = 2 },
    { id = "焰渊灵境", beasts = "兆兽三、异兽三、神灵二，多伏击之属，炎暗之气重", trait = "天晶×1.5，瘴气加倍", unlockLevel = 2 },
    { id = "幽潭灵境", beasts = "兆兽四、异兽三、神灵二，多领地之属，水暗之气深", trait = "水面最多，雾气浓重", unlockLevel = 3 },
    { id = "虚空灵境", beasts = "万兽齐聚，六灵十异八兆，凡二十四种尽出", trait = "收缩×1.2，SSR+5%", unlockLevel = 5 },
}

local SCHOOLS = {
    { id = "trace",    name = "追迹流", desc = "循迹辨踪，感通灵脉，神兽踪迹无所遁形", color = nil },
    { id = "suppress", name = "压制流", desc = "以力镇之，封印术法精进，压制之术大成", color = nil },
    { id = "evac",     name = "撤离流", desc = "明哲保身，趋吉避凶，全身而退方为上策", color = nil },
    { id = "greed",    name = "贪渊流", desc = "涉险探渊，以身犯难，险中求得奇珍异宝", color = nil, unlockLevel = 4 },
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
    -- 恢复类道具
    { id = "lingquanWan", name = "灵泉丸", category = "recovery", desc = "+2HP，使用耗时1秒", usage = "点击使用" },
    { id = "jianzhulu",   name = "绛珠露", category = "recovery", desc = "+5HP，使用耗时0.5秒", usage = "点击使用" },
    { id = "fusufu",      name = "复苏符", category = "recovery", desc = "HP归零自动+4HP", usage = "被动触发" },
}

function PrepareScreen.new(params)
    local self = setmetatable({}, PrepareScreen)
    self.fadeIn = 0
    self.t = 0
    self.step = 1
    self.selectedBiome = nil
    self.selectedSchool = nil
    self.selectedSkill = nil
    self.selectedItems = {}
    self.buttons = {}
    self.itemScrollY = 0
    self.itemContentH = 0
    return self
end

function PrepareScreen:onEnter()
    self.fadeIn = 0
    self.step = 1
    self.selectedBiome = nil
    self.selectedSchool = nil
    self.selectedSkill = nil
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
    local stepLabels = { "选择灵境", "选择流派", "选择技能", "配置道具" }
    for i = 1, 4 do
        local sx = logW * (0.125 + (i - 1) * 0.25)
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
        self:renderSkillSelect(vg, logW, logH, alpha)
    elseif self.step == 4 then
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

        -- 特色（右上角，与灵境名同行）
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, textAlpha * 0.6 * alpha))
        nvgText(vg, (logW + cardW) * 0.5 - 14, cy + cardH * 0.3, biome.trait)

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
        self:renderNextButton(vg, logW, logH, alpha, "选择技能 >")
    end
end

------------------------------------------------------------
-- Step 3: 背刺技能选择
------------------------------------------------------------

function PrepareScreen:renderSkillSelect(vg, logW, logH, alpha)
    local P = InkPalette

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.10, "选择背刺技能")

    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.6 * alpha))
    nvgText(vg, logW * 0.5, logH * 0.14, "每次探索携带一种技能")

    local cardW = logW * 0.85
    local cardH = logH * 0.10
    local startY = logH * 0.18
    local gap = 6

    for i, skillId in ipairs(SkillSystem.SKILL_ORDER) do
        local skill = SkillSystem.SKILLS[skillId]
        local cy = startY + (i - 1) * (cardH + gap)
        local unlocked, lockDesc = SkillSystem.isUnlocked(skillId)
        local selected = self.selectedSkill == skillId

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, 6)
        local bgColor = selected and P.cinnabar or P.jade
        local bgAlpha = selected and 0.15 or 0.05
        nvgFillColor(vg, nvgRGBAf(bgColor.r, bgColor.g, bgColor.b, bgAlpha * alpha))
        nvgFill(vg)

        if selected then
            BrushStrokes.inkRect(vg, (logW - cardW) * 0.5, cy, cardW, cardH, P.cinnabar, 0.5, i * 23)
        end

        local textAlpha = unlocked and 0.85 or 0.3
        local leftX = (logW - cardW) * 0.5 + 14

        -- 技能类型标记
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local catColor = (skill.category == "throw") and P.azure or P.indigo
        nvgFillColor(vg, nvgRGBAf(catColor.r, catColor.g, catColor.b, textAlpha * 0.7 * alpha))
        local catLabel = (skill.category == "throw") and "投掷" or "法术"
        nvgText(vg, leftX, cy + cardH * 0.25, catLabel)

        -- 技能名
        nvgFontSize(vg, 15)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, textAlpha * alpha))
        nvgText(vg, leftX + 30, cy + cardH * 0.25, skill.name)

        -- 次数
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, textAlpha * 0.7 * alpha))
        nvgText(vg, (logW + cardW) * 0.5 - 14, cy + cardH * 0.25, "×" .. skill.maxUses)

        -- 描述 / 锁定提示
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if unlocked then
            nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.65 * alpha))
            nvgText(vg, leftX, cy + cardH * 0.7, skill.desc)
        else
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.5 * alpha))
            nvgText(vg, leftX, cy + cardH * 0.7, lockDesc or "未解锁")
        end

        -- 点击区域
        if unlocked then
            table.insert(self.buttons, {
                type = "skill", skillId = skillId,
                x = (logW - cardW) * 0.5, y = cy, w = cardW, h = cardH,
            })
        end
    end

    if self.selectedSkill then
        self:renderNextButton(vg, logW, logH, alpha, "配置道具 >")
    end
end

------------------------------------------------------------
-- Step 4: 道具配置
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

    -- 双列紧凑布局（按分类分组）
    local groups = {
        { label = "封灵器", cat = "sealer",   color = P.indigo },
        { label = "探索道具", cat = "item",   color = P.jade },
        { label = "恢复道具", cat = "recovery", color = P.cinnabar },
    }
    local margin = 8
    local colGap = 6
    local totalW = logW - margin * 2
    local colW = (totalW - colGap) * 0.5
    local cardH = 56
    local rowGap = 5
    local groupGap = 10
    local scrollY = self.itemScrollY or 0
    local curY = logH * 0.19 + scrollY

    for _, grp in ipairs(groups) do
        -- 分组标签
        curY = curY + 2
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(grp.color.r, grp.color.g, grp.color.b, 0.6 * alpha))
        nvgText(vg, margin, curY + 6, "── " .. grp.label .. " ──")
        curY = curY + 16

        -- 收集本组道具
        local groupItems = {}
        for _, item in ipairs(ITEMS) do
            if item.category == grp.cat then
                table.insert(groupItems, item)
            end
        end

        -- 双列排列
        for idx = 1, #groupItems, 2 do
            for col = 0, 1 do
                local item = groupItems[idx + col]
                if not item then break end

                local cx = margin + col * (colW + colGap)
                local cy = curY
                local stock = GameState.getResource(item.id)
                local sel = self.selectedItems[item.id] or 0

                -- 卡片背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx, cy, colW, cardH, 4)
                nvgFillColor(vg, nvgRGBAf(grp.color.r, grp.color.g, grp.color.b, 0.05 * alpha))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, cx, cy, colW, cardH, 4)
                nvgStrokeWidth(vg, 0.5)
                nvgStrokeColor(vg, nvgRGBAf(grp.color.r, grp.color.g, grp.color.b, 0.15 * alpha))
                nvgStroke(vg)

                -- 第一行：名称 + 库存
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.8 * alpha))
                nvgText(vg, cx + 8, cy + 12, item.name)

                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.55 * alpha))
                nvgText(vg, cx + colW - 6, cy + 12, "库存:" .. stock)

                -- 第二行：描述
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
                nvgText(vg, cx + 8, cy + 27, item.desc or "")

                -- 第三行：使用方式 + 数量控制
                if item.usage then
                    local usageColor = (item.usage == "点击激活" or item.usage == "点击使用") and P.jade or P.azure
                    nvgFontSize(vg, 8)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgFillColor(vg, nvgRGBAf(usageColor.r, usageColor.g, usageColor.b, 0.5 * alpha))
                    nvgText(vg, cx + 8, cy + 42, item.usage)
                end

                -- 数量控制：[-] 数字 [+]
                local btnR = 10
                local ctrlCY = cy + 43
                local plusCX = cx + colW - 10
                local minusCX = plusCX - 46
                local numCX = (minusCX + plusCX) * 0.5

                nvgBeginPath(vg)
                nvgCircle(vg, minusCX, ctrlCY, btnR)
                nvgStrokeWidth(vg, 0.8)
                nvgStrokeColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.35 * alpha))
                nvgStroke(vg)
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.55 * alpha))
                nvgText(vg, minusCX, ctrlCY, "-")

                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.8 * alpha))
                nvgText(vg, numCX, ctrlCY, tostring(sel))

                nvgBeginPath(vg)
                nvgCircle(vg, plusCX, ctrlCY, btnR)
                nvgStrokeWidth(vg, 0.8)
                nvgStrokeColor(vg, nvgRGBAf(grp.color.r, grp.color.g, grp.color.b, 0.45 * alpha))
                nvgStroke(vg)
                nvgFontSize(vg, 12)
                nvgFillColor(vg, nvgRGBAf(grp.color.r, grp.color.g, grp.color.b, 0.65 * alpha))
                nvgText(vg, plusCX, ctrlCY, "+")

                table.insert(self.buttons, {
                    type = "minus", itemId = item.id,
                    x = minusCX - btnR, y = ctrlCY - btnR, w = btnR * 2, h = btnR * 2,
                })
                table.insert(self.buttons, {
                    type = "plus", itemId = item.id,
                    x = plusCX - btnR, y = ctrlCY - btnR, w = btnR * 2, h = btnR * 2,
                })
            end
            curY = curY + cardH + rowGap
        end
        curY = curY + groupGap
    end

    -- 记录内容总高度（用于滚动限制）
    self.itemContentH = curY - scrollY - logH * 0.19

    -- 出发按钮（固定在底部）
    local mainBtnW = 180
    local mainBtnH = 44
    local mainBtnX = (logW - mainBtnW) * 0.5
    local mainBtnY = logH - mainBtnH - 12
    local breathe = 1.0 + math.sin(self.t * 2) * 0.03

    -- 按钮背景遮罩（底部渐变）
    nvgBeginPath(vg)
    nvgRect(vg, 0, mainBtnY - 20, logW, mainBtnH + 32)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.9))
    nvgFill(vg)

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
    -- 道具配置页支持上下拖拽滚动
    if action == "drag_y" and self.step == 4 then
        local maxScroll = math.max(0, self.itemContentH - (graphics:GetHeight() / graphics:GetDPR()) * 0.60)
        self.itemScrollY = math.max(-maxScroll, math.min(0, self.itemScrollY + sy))
        return true
    end

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

            elseif btn.type == "skill" then
                self.selectedSkill = btn.skillId
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
                SessionState.selectedSkill = self.selectedSkill

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
