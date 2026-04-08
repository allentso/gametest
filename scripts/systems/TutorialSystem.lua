--- 新手引导 - 触发式提示
local EventBus = require("systems.EventBus")

local TutorialSystem = {}

TutorialSystem.step = 0
TutorialSystem.active = false

local STEPS = {
    { id = "welcome",     trigger = "enter_map",          message = "欢迎来到灵境" },
    { id = "collect",     trigger = "lingshi >= 5",       message = "灵石可以合成封灵器" },
    { id = "investigate", trigger = "clue_collected",     message = "发现了异兽的踪迹！" },
    { id = "first_beast", trigger = "beast_spawned",      message = "异兽出现了！接近它" },
    { id = "suppress",    trigger = "suppress_start",     message = "在目标区域点击！" },
    { id = "captured",    trigger = "beast_captured",     message = "需要撤离才能带走它" },
    { id = "evacuate",    trigger = "near_evac_point",    message = "前往传送阵等待撤离" },
    { id = "complete",    trigger = "evacuation_success", message = "异兽已入图鉴" },
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
