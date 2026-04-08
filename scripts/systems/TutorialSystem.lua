--- 新手引导 - 触发式提示
local EventBus = require("systems.EventBus")

local TutorialSystem = {}

TutorialSystem.step = 0
TutorialSystem.active = false

local STEPS = {
    { id = "lobby",       trigger = "enter_lobby",     message = "欢迎来到灵境，选择你的封印流派，然后踏入灵境" },
    { id = "prepare",     trigger = "enter_prepare",   message = "选择一个灵境——翠谷适合初学者" },
    { id = "welcome",     trigger = "enter_map",       message = "这是封印师的眼，迷雾中只有你见过的地方才会留存" },
    { id = "collect",     trigger = "collect",          message = "灵石可以合成封灵器，深入才有更珍贵的材料" },
    { id = "bamboo",      trigger = "enter_bamboo",     message = "竹林能遮掩你的身影，接近异兽时善用地形" },
    { id = "investigate", trigger = "investigate",      message = "发现了异兽的踪迹！继续收集线索，它就会出现" },
    { id = "first_beast", trigger = "beast_spawned",    message = "异兽出现了！从背后接近，背刺有加成" },
    { id = "suppress",    trigger = "suppress",         message = "看清楚目标区域，在指针进入时点击！" },
    { id = "captured",    trigger = "captured",         message = "捕获成功！需要到撤离法阵才能带它离开" },
    { id = "complete",    trigger = "evacuation_done",  message = "异兽已入图鉴，封灵师手记更新。继续探索吧" },
}

function TutorialSystem.start()
    TutorialSystem.step = 1
    TutorialSystem.active = true
end

function TutorialSystem.checkTrigger(triggerType, data)
    if not TutorialSystem.active then return end
    if TutorialSystem.step > #STEPS then
        TutorialSystem.active = false
        return
    end
    local current = STEPS[TutorialSystem.step]
    if current.trigger == triggerType then
        EventBus.emit("tutorial_message", current.message)
        TutorialSystem.step = TutorialSystem.step + 1
    end
end

function TutorialSystem.getCurrentStep()
    if TutorialSystem.step > 0 and TutorialSystem.step <= #STEPS then
        return STEPS[TutorialSystem.step]
    end
    return nil
end

function TutorialSystem.isActive()
    return TutorialSystem.active
end

return TutorialSystem
