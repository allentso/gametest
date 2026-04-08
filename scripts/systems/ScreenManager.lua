--- 屏幕管理器 - 栈式 push/pop/switch + 生命周期
local EventBus = require("systems.EventBus")

local ScreenManager = {}
local stack = {}

function ScreenManager.switch(screenClass, params)
    for i = #stack, 1, -1 do
        if stack[i].onExit then stack[i]:onExit() end
        EventBus.off(nil, stack[i])
    end
    stack = {}
    local screen = screenClass.new(params)
    table.insert(stack, screen)
    if screen.onEnter then screen:onEnter() end
    EventBus.emit("screen_changed", screen, nil)
end

function ScreenManager.push(screenClass, params)
    local current = stack[#stack]
    if current and current.onPause then current:onPause() end
    local screen = screenClass.new(params)
    table.insert(stack, screen)
    if screen.onEnter then screen:onEnter() end
end

function ScreenManager.pop()
    local top = stack[#stack]
    if top then
        if top.onExit then top:onExit() end
        EventBus.off(nil, top)
        table.remove(stack)
    end
    local current = stack[#stack]
    if current and current.onResume then current:onResume() end
end

function ScreenManager.current()
    return stack[#stack]
end

function ScreenManager.update(dt)
    local top = stack[#stack]
    if top and top.isModal then
        if top.update then top:update(dt) end
    else
        for _, s in ipairs(stack) do
            if s.update then s:update(dt) end
        end
    end
end

function ScreenManager.render(vg, logW, logH, t)
    for _, s in ipairs(stack) do
        if s.render then s:render(vg, logW, logH, t) end
    end
end

-- tap 合成状态
local tapState = { active = false, x = 0, y = 0, time = 0 }
local TAP_DIST = 15    -- 最大偏移(逻辑像素)
local TAP_TIME = 0.4   -- 最大间隔(秒)

function ScreenManager.onInput(action, sx, sy)
    local top = stack[#stack]
    if not top or not top.onInput then return false end

    -- 合成 tap: down 记录 → up 时判断距离和时间
    if action == "down" then
        tapState.active = true
        tapState.x = sx
        tapState.y = sy
        tapState.time = os.clock()
    elseif action == "up" and tapState.active then
        tapState.active = false
        local dx = math.abs(sx - tapState.x)
        local dy = math.abs(sy - tapState.y)
        local dt = os.clock() - tapState.time
        if dx < TAP_DIST and dy < TAP_DIST and dt < TAP_TIME then
            -- 先发送 tap 事件
            local handled = top:onInput("tap", sx, sy)
            if handled then return true end
        end
    elseif action == "move" then
        -- 移动超出范围则取消 tap
        if tapState.active then
            local dx = math.abs(sx - tapState.x)
            local dy = math.abs(sy - tapState.y)
            if dx >= TAP_DIST or dy >= TAP_DIST then
                tapState.active = false
            end
        end
    end

    -- 原始事件也转发（ExploreScreen 等需要 down/move/up）
    return top:onInput(action, sx, sy)
end

function ScreenManager.stackSize()
    return #stack
end

return ScreenManager
