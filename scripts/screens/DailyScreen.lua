--- 每日修行屏 - 签到 + 任务
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local DailySystem = require("systems.DailySystem")

local DailyScreen = {}
DailyScreen.__index = DailyScreen

function DailyScreen.new(params)
    local self = setmetatable({}, DailyScreen)
    self.fadeIn = 0
    self.t = 0
    self.buttons = {}
    return self
end

function DailyScreen:onEnter()
    self.fadeIn = 0
end

function DailyScreen:update(dt)
    self.t = self.t + dt
    if self.fadeIn < 1 then
        self.fadeIn = math.min(1, self.fadeIn + dt * 1.8)
    end
end

function DailyScreen:render(vg, logW, logH, t)
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
    nvgText(vg, logW * 0.5, logH * 0.05, "每日修行")

    -- 返回
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.65 * alpha))
    nvgText(vg, 16, logH * 0.05, "< 返回")

    self.buttons = {}
    table.insert(self.buttons, { type = "back", x = 0, y = logH * 0.02, w = 80, h = 30 })

    -- 7天签到日历
    local calY = logH * 0.12
    local calW = logW * 0.85
    local calX = (logW - calW) * 0.5
    local cellW = calW / 7
    local cellH = logH * 0.08
    local currentDay = DailySystem.getLoginDay(GameState.data.loginDays or 1)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for i = 1, 7 do
        local cx = calX + (i - 1) * cellW + cellW * 0.5
        local cy = calY + cellH * 0.5
        local isSigned = i < currentDay
        local isCurrent = (i == currentDay)

        -- 格子
        nvgBeginPath(vg)
        nvgRoundedRect(vg, calX + (i - 1) * cellW + 2, calY + 2, cellW - 4, cellH - 4, 4)

        if isCurrent then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.12 * alpha))
        elseif isSigned then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.08 * alpha))
        else
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, 0.04 * alpha))
        end
        nvgFill(vg)

        -- 天数
        nvgFontSize(vg, 13)
        if isCurrent then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.80 * alpha))
        elseif isSigned then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.70 * alpha))
        else
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, 0.50 * alpha))
        end
        nvgText(vg, cx, cy - 6, tostring(i))

        -- 签到标记
        if isSigned then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.60 * alpha))
            nvgText(vg, cx, cy + 10, "已签")
        end

        -- 奖励预览
        local reward = DailySystem.loginRewards[i]
        if reward and not isSigned then
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, 0.45 * alpha))
            local rewardText = ""
            for k, v in pairs(reward) do
                rewardText = k
                break
            end
            nvgText(vg, cx, cy + 10, rewardText)
        end
    end

    -- 分隔线
    local taskStartY = calY + cellH + 20
    BrushStrokes.inkLine(vg, logW * 0.1, taskStartY - 8, logW * 0.9, taskStartY - 8,
        1.0, InkPalette.inkWash, 0.20 * alpha, 88)

    -- 任务卡片
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.75 * alpha))
    nvgText(vg, logW * 0.1, taskStartY, "每日任务")

    local taskCardH = logH * 0.08
    local taskGap = 8
    local tStartY = taskStartY + 18

    for i, task in ipairs(DailySystem.tasks) do
        local ty = tStartY + (i - 1) * (taskCardH + taskGap)
        local progress = DailySystem.progress[task.id] or 0
        local isComplete = progress >= task.target
        local claimed = GameState.data.dailyClaimed and GameState.data.dailyClaimed[task.id]

        -- 卡片
        local taskColor = claimed and InkPalette.inkWash
            or isComplete and InkPalette.gold
            or InkPalette.inkLight

        nvgBeginPath(vg)
        nvgRoundedRect(vg, logW * 0.08, ty, logW * 0.84, taskCardH, 4)
        nvgFillColor(vg, nvgRGBAf(taskColor.r, taskColor.g, taskColor.b, 0.06 * alpha))
        nvgFill(vg)

        -- 任务描述
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.75 * alpha))
        nvgText(vg, logW * 0.12, ty + taskCardH * 0.5, task.desc)

        -- 进度
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 12)
        if claimed then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkWash.r, InkPalette.inkWash.g, InkPalette.inkWash.b, 0.50 * alpha))
            nvgText(vg, logW * 0.88, ty + taskCardH * 0.5, "已领取")
        elseif isComplete then
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.70 * alpha))
            nvgText(vg, logW * 0.88, ty + taskCardH * 0.5, "可领取")
            table.insert(self.buttons, {
                type = "claim", taskId = task.id,
                x = logW * 0.70, y = ty, w = logW * 0.22, h = taskCardH
            })
        else
            nvgFillColor(vg, nvgRGBAf(
                InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.60 * alpha))
            nvgText(vg, logW * 0.88, ty + taskCardH * 0.5,
                string.format("%d/%d", progress, task.target))
        end
    end
end

function DailyScreen:onInput(action, sx, sy)
    if action ~= "tap" then return false end

    for _, btn in ipairs(self.buttons) do
        if sx >= btn.x and sx <= btn.x + btn.w
           and sy >= btn.y and sy <= btn.y + btn.h then
            if btn.type == "back" then
                local LobbyScreen = require("screens.LobbyScreen")
                ScreenManager.switch(LobbyScreen)
                return true
            elseif btn.type == "claim" then
                local task = DailySystem.getTask(btn.taskId)
                if task and task.reward then
                    for resType, amount in pairs(task.reward) do
                        GameState.addResource(resType, amount)
                    end
                    if not GameState.data.dailyClaimed then
                        GameState.data.dailyClaimed = {}
                    end
                    GameState.data.dailyClaimed[btn.taskId] = true
                    GameState.save()
                end
                return true
            end
        end
    end
    return false
end

return DailyScreen
