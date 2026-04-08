--- 输入路由器 - 分层热区注册/分发
local ScreenManager = require("systems.ScreenManager")

local InputRouter = {}
local hotZones = {}

--- 注册热区
function InputRouter.register(rect, callback, layer, owner)
    table.insert(hotZones, {
        rect = rect,        -- {x, y, w, h} 屏幕坐标
        callback = callback,
        layer = layer,
        owner = owner,
    })
end

--- 按 owner 注销
function InputRouter.unregister(owner)
    for i = #hotZones, 1, -1 do
        if hotZones[i].owner == owner then
            table.remove(hotZones, i)
        end
    end
end

--- 分发点击事件
function InputRouter.dispatch(sx, sy, action)
    -- 按层级从高到低排序
    table.sort(hotZones, function(a, b) return a.layer > b.layer end)
    for _, zone in ipairs(hotZones) do
        local r = zone.rect
        if sx >= r.x and sx <= r.x + r.w and sy >= r.y and sy <= r.y + r.h then
            zone.callback(action, sx, sy)
            return true
        end
    end
    -- 未命中热区则分发给当前屏幕
    return ScreenManager.onInput(action, sx, sy)
end

--- 清空所有热区
function InputRouter.clear()
    hotZones = {}
end

-- 触摸追踪
InputRouter.touchStart = nil
InputRouter.touchStartTime = 0
InputRouter.CLICK_THRESHOLD = 0.15
InputRouter.DRAG_THRESHOLD = 8

return InputRouter
