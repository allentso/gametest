--- 异兽 AI 状态机 + 朝向系统
local CollisionSystem = require("systems.CollisionSystem")

local BeastAI = {}

BeastAI.STATE = {
    IDLE     = "idle",
    WANDER   = "wander",
    ALERT    = "alert",
    FLEE     = "flee",
    HIDDEN   = "hidden",
    SUPPRESS = "suppress",
    CAPTURED = "captured",
}

BeastAI.SENSE_RANGE = { R = 3, SR = 4, SSR = 6 }

function BeastAI.update(beast, dt, playerX, playerY, map)
    local state = beast.aiState

    if state == "idle" then
        beast.idleTimer = (beast.idleTimer or 0) + dt
        if beast.idleTimer > (beast.idleDuration or 3) then
            beast.aiState = "wander"
            beast.idleTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        end

    elseif state == "wander" then
        local arrived = BeastAI.moveToward(beast, beast.wanderTarget, dt, beast.baseSpeed or 1.5, map)
        if arrived then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 3
        end
        -- 感知玩家
        local dist = BeastAI.distTo(beast, playerX, playerY)
        local senseRange = BeastAI.SENSE_RANGE[beast.quality] or 3
        if dist < senseRange then
            local contactType = BeastAI.getContactType(beast, playerX, playerY)
            if contactType == "front" then
                if beast.quality == "SSR" then
                    beast.aiState = "flee"
                    beast.facing = math.atan2(beast.y - playerY, beast.x - playerX)
                else
                    beast.aiState = "alert"
                    beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
                end
            elseif contactType == "side" and beast.quality == "SSR" then
                beast.aiState = "alert"
                beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            end
        end

    elseif state == "alert" then
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        beast.alertTimer = (beast.alertTimer or 0) + dt
        local dist = BeastAI.distTo(beast, playerX, playerY)
        if dist < 2 then
            beast.aiState = "flee"
        elseif beast.alertTimer > 5 then
            beast.aiState = "wander"
            beast.alertTimer = 0
        end

    elseif state == "flee" then
        local angle = math.atan2(beast.y - playerY, beast.x - playerX)
        beast.facing = angle
        local speed = 3.5
        local dx = math.cos(angle) * speed * dt
        local dy = math.sin(angle) * speed * dt
        CollisionSystem.tryMove(beast, dx, dy, map)
        if BeastAI.distTo(beast, playerX, playerY) > 8 then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 2
            beast.alertTimer = 0
        end

    elseif state == "hidden" then
        -- 等待追踪系统触发
    elseif state == "suppress" or state == "captured" then
        -- 不做任何事
    end
end

function BeastAI.moveToward(beast, target, dt, speed, map)
    if not target then return true end
    local dx = target.x - beast.x
    local dy = target.y - beast.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.1 then return true end
    beast.facing = math.atan2(dy, dx)
    local step = math.min(speed * dt, dist)
    local mx = (dx / dist) * step
    local my = (dy / dist) * step
    if map then
        CollisionSystem.tryMove(beast, mx, my, map)
    else
        beast.x = beast.x + mx
        beast.y = beast.y + my
    end
    return false
end

function BeastAI.distTo(beast, px, py)
    local dx = beast.x - px
    local dy = beast.y - py
    return math.sqrt(dx * dx + dy * dy)
end

function BeastAI.randomNearby(beast, map, radius)
    for attempt = 1, 10 do
        local tx = beast.x + (math.random() - 0.5) * radius * 2
        local ty = beast.y + (math.random() - 0.5) * radius * 2
        if not map:isBlocked(math.floor(tx), math.floor(ty)) then
            return { x = tx, y = ty }
        end
    end
    return { x = beast.x, y = beast.y }
end

--- 获取接触方向（back/side/front）
function BeastAI.getContactType(beast, playerX, playerY)
    local toPlayerAngle = math.atan2(playerY - beast.y, playerX - beast.x)
    local diff = toPlayerAngle - (beast.facing or 0)
    -- 规范化到 [-π, π]
    while diff > math.pi do diff = diff - math.pi * 2 end
    while diff < -math.pi do diff = diff + math.pi * 2 end
    local absDiff = math.abs(diff)

    if absDiff > math.pi * 2 / 3 then
        return "back"     -- 背后 ±60° → 偷袭
    elseif absDiff > math.pi / 3 then
        return "side"     -- 侧面
    else
        return "front"    -- 正面
    end
end

--- 创建异兽实体
function BeastAI.createBeast(beastData, x, y, quality)
    return {
        id = beastData.id,
        type = beastData.id,
        name = beastData.name,
        element = beastData.element,
        quality = quality or "R",
        x = x,
        y = y,
        halfW = (beastData.bodySize or 0.4) * 0.8,
        halfH = (beastData.bodySize or 0.4) * 0.8,
        facing = math.random() * math.pi * 2,
        aiState = (quality == "R") and "wander" or "hidden",
        idleTimer = 0,
        idleDuration = 2 + math.random() * 3,
        alertTimer = 0,
        wanderTarget = nil,
        ambushBonus = false,
        baseSpeed = beastData.baseSpeed or 1.5,
        bodySize = beastData.bodySize or 0.4,
        senseRange = beastData.senseRange or 3,
    }
end

return BeastAI
