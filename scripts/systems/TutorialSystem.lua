--- 新手引导 - 触发式提示
local EventBus = require("systems.EventBus")

local TutorialSystem = {}

TutorialSystem.step = 0
TutorialSystem.active = false

local STEPS = {
    { id = "welcome",     trigger = "enter_map",      message = "欢迎来到灵境，探索并寻找异兽踪迹" },
    { id = "collect",     trigger = "collect",         message = "灵石可以合成封灵器" },
    { id = "investigate", trigger = "investigate",     message = "发现了异兽的踪迹！继续收集线索" },
    { id = "first_beast", trigger = "beast_spawned",   message = "异兽出现了！从背后接近它" },
    { id = "suppress",    trigger = "suppress",        message = "在目标区域点击以压制异兽！" },
    { id = "captured",    trigger = "captured",        message = "捕获成功！需要撤离才能带走它" },
    { id = "evacuate",    trigger = "evacuate",        message = "前往传送阵，站定等待撤离" },
    { id = "complete",    trigger = "evacuation_done", message = "异兽已入图鉴，恭喜！" },
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
