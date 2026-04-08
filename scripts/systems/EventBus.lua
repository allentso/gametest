--- 事件总线 - on/off/emit + owner 批量注销
local EventBus = {}
local listeners = {}

function EventBus.on(event, fn, owner)
    if not listeners[event] then listeners[event] = {} end
    table.insert(listeners[event], { fn = fn, owner = owner })
end

function EventBus.off(event, owner)
    if event == nil then
        for ev, list in pairs(listeners) do
            for i = #list, 1, -1 do
                if list[i].owner == owner then
                    table.remove(list, i)
                end
            end
        end
        return
    end
    if not listeners[event] then return end
    for i = #listeners[event], 1, -1 do
        if listeners[event][i].owner == owner then
            table.remove(listeners[event], i)
        end
    end
end

function EventBus.emit(event, ...)
    if not listeners[event] then return end
    for _, entry in ipairs(listeners[event]) do
        entry.fn(...)
    end
end

function EventBus.clear()
    listeners = {}
end

return EventBus
