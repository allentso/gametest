--- 碰撞系统 - 分轴碰撞 + 角落滑动
local CollisionSystem = {}

--- 尝试移动实体，自动处理碰撞
function CollisionSystem.tryMove(entity, dx, dy, map)
    local newX = entity.x + dx
    local newY = entity.y + dy
    local halfW = entity.halfW or 0.35
    local halfH = entity.halfH or 0.35

    -- 整体无碰撞
    if not CollisionSystem.blocked(newX, newY, halfW, halfH, map) then
        entity.x = newX
        entity.y = newY
        return
    end

    -- 分轴：仅X
    if dx ~= 0 and not CollisionSystem.blocked(entity.x + dx, entity.y, halfW, halfH, map) then
        entity.x = entity.x + dx
        return
    end

    -- 分轴：仅Y
    if dy ~= 0 and not CollisionSystem.blocked(entity.x, entity.y + dy, halfW, halfH, map) then
        entity.y = entity.y + dy
        return
    end

    -- 角落滑动
    local nudge = 0.3
    if dx ~= 0 then
        for _, n in ipairs({ nudge, -nudge }) do
            if not CollisionSystem.blocked(entity.x + dx, entity.y + n * math.abs(dx), halfW, halfH, map) then
                entity.x = entity.x + dx
                entity.y = entity.y + n * math.abs(dx)
                return
            end
        end
    end
    if dy ~= 0 then
        for _, n in ipairs({ nudge, -nudge }) do
            if not CollisionSystem.blocked(entity.x + n * math.abs(dy), entity.y + dy, halfW, halfH, map) then
                entity.x = entity.x + n * math.abs(dy)
                entity.y = entity.y + dy
                return
            end
        end
    end
end

--- 四角碰撞检测
function CollisionSystem.blocked(x, y, hw, hh, map)
    local checks = {
        { x - hw, y - hh }, { x + hw, y - hh },
        { x - hw, y + hh }, { x + hw, y + hh },
    }
    for _, c in ipairs(checks) do
        if map:isBlocked(math.floor(c[1]), math.floor(c[2])) then
            return true
        end
    end
    return false
end

return CollisionSystem
