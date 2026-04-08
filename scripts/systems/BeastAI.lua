--- 异兽 AI 状态机 + 朝向系统 + 个性行为
--- 白泽凝视、风鸣隐形、水蛟水面加速、雷翼高速冲刺窗口
--- 墨鸦墨迹、石灵石化防御、土偶不逃跑
local CollisionSystem = require("systems.CollisionSystem")
local Config = require("Config")
local EventBus = require("systems.EventBus")

local BeastAI = {}

BeastAI.STATE = {
    IDLE       = "idle",
    WANDER     = "wander",
    ALERT      = "alert",
    FLEE       = "flee",
    HIDDEN     = "hidden",
    SUPPRESS   = "suppress",
    CAPTURED   = "captured",
    PANIC      = "panic",
    GAZE       = "gaze",
    PETRIFIED  = "petrified",
    BURST      = "burst",
    BURST_STOP = "burst_stop",
}

-- 品质额外感知加成（叠加到异兽自身 senseRange 上）
BeastAI.QUALITY_SENSE_BONUS = { R = 0, SR = 1, SSR = 2 }

------------------------------------------------------------
-- Main update
------------------------------------------------------------
function BeastAI.update(beast, dt, playerX, playerY, map, options)
    options = options or {}
    local state = beast.aiState
    local playerInBamboo = options.playerInBamboo or false
    local playerMoving = options.playerMoving
    if playerMoving == nil then playerMoving = true end

    -- 石灵石化防御倒计时
    if beast.petrifyTimer and beast.petrifyTimer > 0 then
        beast.petrifyTimer = beast.petrifyTimer - dt
        if beast.petrifyTimer <= 0 then
            beast.petrifyTimer = 0
            if beast.aiState == "petrified" then
                beast.aiState = "idle"
                beast.idleDuration = 1
            end
        end
    end

    -- 风鸣隐形：wander状态下透明，其他状态可见
    if beast.id == "007" then
        beast.invisible = (state == "wander" or state == "idle")
        -- 竹林中无法隐形
        if playerInBamboo and beast.invisible then
            local bTileX = math.floor(beast.x)
            local bTileY = math.floor(beast.y)
            local bTile = map and map.getTile and map:getTile(bTileX, bTileY)
            if bTile and bTile.type == "bamboo" then
                beast.invisible = false
            end
        end
    else
        beast.invisible = false
    end

    -- 墨鸦墨迹：flee状态下每0.5秒生成墨迹
    if beast.id == "010" and state == "flee" then
        beast.inkTimer = (beast.inkTimer or 0) + dt
        if beast.inkTimer >= 0.5 then
            beast.inkTimer = 0
            EventBus.emit("ink_patch_created", {
                x = beast.x, y = beast.y, duration = 20,
            })
        end
    end

    if state == "idle" then
        beast.idleTimer = (beast.idleTimer or 0) + dt
        if beast.idleTimer > (beast.idleDuration or 3) then
            beast.aiState = "wander"
            beast.idleTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        end

    elseif state == "wander" then
        local speed = beast.baseSpeed or 1.5
        -- 水蛟水面加速
        if beast.id == "006" then
            speed = speed + BeastAI.getWaterBonus(beast, map)
        end
        local arrived = BeastAI.moveToward(beast, beast.wanderTarget, dt, speed, map)
        if arrived then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 3
        end

        local dist = BeastAI.distTo(beast, playerX, playerY)
        local senseRange = (beast.senseRange or 3) + (BeastAI.QUALITY_SENSE_BONUS[beast.quality] or 0)
        if playerInBamboo then senseRange = senseRange - 2 end
        if options.playerInDanger then senseRange = senseRange - 1 end
        -- 玄狐在竹林中感知缩减
        if beast.id == "001" and playerInBamboo then
            senseRange = math.min(senseRange, 1.5)
        end
        senseRange = math.max(1, senseRange)

        if dist < senseRange then
            local contactType = BeastAI.getContactType(beast, playerX, playerY)
            BeastAI.onSensed(beast, contactType, playerX, playerY, map)
        end

    elseif state == "alert" then
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        beast.alertTimer = (beast.alertTimer or 0) + dt
        local dist = BeastAI.distTo(beast, playerX, playerY)
        if dist < 2 then
            -- 土偶不逃跑，只转身面对
            if beast.id == "008" then
                beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            else
                beast.aiState = "flee"
            end
        elseif beast.alertTimer > 5 then
            beast.aiState = "wander"
            beast.alertTimer = 0
        end

    elseif state == "flee" then
        local angle = math.atan2(beast.y - playerY, beast.x - playerX)
        beast.facing = angle
        local speed = 3.5
        -- 水蛟水面加速
        if beast.id == "006" then
            speed = speed + BeastAI.getWaterBonus(beast, map)
        end
        local dx = math.cos(angle) * speed * dt
        local dy = math.sin(angle) * speed * dt
        CollisionSystem.tryMove(beast, dx, dy, map)
        BeastAI.clampToMap(beast)
        if BeastAI.distTo(beast, playerX, playerY) > 8 then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 2
            beast.alertTimer = 0
        end

    elseif state == "gaze" then
        -- 白泽凝视：朝玩家走近1格，然后等待
        if not beast.gazePhase then beast.gazePhase = "approach" end

        if beast.gazePhase == "approach" then
            local dist = BeastAI.distTo(beast, playerX, playerY)
            if dist > 3.0 then
                local target = {
                    x = playerX + (beast.x - playerX) / dist * 3.0,
                    y = playerY + (beast.y - playerY) / dist * 3.0,
                }
                BeastAI.moveToward(beast, target, dt, 1.0, map)
                beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            else
                beast.gazePhase = "watching"
                beast.gazeWatchTimer = 0
            end
        elseif beast.gazePhase == "watching" then
            beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            if playerMoving then
                -- 玩家移动→白泽逃跑
                beast.aiState = "flee"
                beast.gazePhase = nil
                beast.gazeWatchTimer = nil
            else
                beast.gazeWatchTimer = (beast.gazeWatchTimer or 0) + dt
                if beast.gazeWatchTimer >= 3.0 then
                    -- 玩家静止3秒→白泽放下警戒
                    beast.guardLowered = true
                    beast.ambushBonus = true
                    beast.aiState = "idle"
                    beast.idleDuration = 8
                    beast.gazePhase = nil
                    beast.gazeWatchTimer = nil
                end
            end
        end

    elseif state == "burst" then
        -- 雷翼高速冲刺3秒
        beast.burstTimer = (beast.burstTimer or 0) + dt
        if not beast.burstTarget then
            local angle = math.random() * math.pi * 2
            beast.burstTarget = {
                x = beast.x + math.cos(angle) * 8,
                y = beast.y + math.sin(angle) * 8,
            }
        end
        local speed = (beast.baseSpeed or 2.5) * 2
        BeastAI.moveToward(beast, beast.burstTarget, dt, speed, map)
        if beast.burstTimer >= 3.0 then
            beast.aiState = "burst_stop"
            beast.burstTimer = 0
            beast.burstTarget = nil
        end

    elseif state == "burst_stop" then
        -- 雷翼停止1.5秒（追击窗口）
        beast.burstStopTimer = (beast.burstStopTimer or 0) + dt
        beast.burstWindow = true
        if beast.burstStopTimer >= 1.5 then
            beast.aiState = "wander"
            beast.burstStopTimer = 0
            beast.burstWindow = false
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        end

    elseif state == "petrified" then
        -- 石灵石化防御：不可操作，等待timer清零（由上方petrifyTimer处理）

    elseif state == "panic" then
        if not beast.panicTarget then
            beast.panicTarget = BeastAI.randomNearby(beast, map, 6)
        end
        local arrived = BeastAI.moveToward(beast, beast.panicTarget, dt, 3.5, map)
        if arrived then
            beast.panicTarget = BeastAI.randomNearby(beast, map, 6)
        end

    elseif state == "hidden" then
        -- 等待追踪系统触发
    elseif state == "suppress" or state == "captured" then
        -- 不做任何事
    end
end

------------------------------------------------------------
-- 感知后的反应（个性化）
------------------------------------------------------------
function BeastAI.onSensed(beast, contactType, playerX, playerY, map)
    local beastId = beast.id

    -- 白泽：不逃跑，进入凝视
    if beastId == "004" then
        if contactType == "front" or contactType == "side" then
            beast.aiState = "gaze"
            beast.gazePhase = "approach"
            beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        end
        return
    end

    -- 土偶：不逃跑，转身面对
    if beastId == "008" then
        beast.aiState = "alert"
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        return
    end

    -- 雷翼：警觉后进入高速冲刺
    if beastId == "003" then
        if contactType == "front" then
            beast.aiState = "burst"
            beast.burstTimer = 0
            beast.burstTarget = nil
            beast.facing = math.atan2(beast.y - playerY, beast.x - playerX)
        elseif contactType == "side" and beast.quality == "SSR" then
            beast.aiState = "burst"
            beast.burstTimer = 0
            beast.burstTarget = nil
        end
        return
    end

    -- 标准反应逻辑
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

------------------------------------------------------------
-- 石灵石化防御（压制失败后调用）
------------------------------------------------------------
function BeastAI.enterPetrify(beast)
    if beast.id ~= "005" then return end
    beast.aiState = "petrified"
    beast.petrifyTimer = 5.0
end

------------------------------------------------------------
-- 水蛟水面速度加成
------------------------------------------------------------
function BeastAI.getWaterBonus(beast, map)
    if not map or not map.getTile then return 0 end
    for dy = -3, 3 do
        for dx = -3, 3 do
            if dx * dx + dy * dy <= 9 then
                local tile = map:getTile(math.floor(beast.x) + dx, math.floor(beast.y) + dy)
                if tile and tile.type == "water" then
                    return 0.8
                end
            end
        end
    end
    return 0
end

------------------------------------------------------------
-- 检查异兽是否在水面附近（供QTE加速判定）
------------------------------------------------------------
function BeastAI.isNearWater(beast, map)
    return BeastAI.getWaterBonus(beast, map) > 0
end

------------------------------------------------------------
-- 强制所有异兽进入panic状态
------------------------------------------------------------
function BeastAI.panicAll(beasts)
    for _, beast in ipairs(beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "suppress"
           and beast.aiState ~= "hidden" then
            beast.aiState = "panic"
            beast.panicTarget = nil
        end
    end
end

------------------------------------------------------------
-- 移动 / 工具函数
------------------------------------------------------------
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
    BeastAI.clampToMap(beast)
    return false
end

function BeastAI.clampToMap(beast)
    local mapW = Config.MAP_WIDTH or 20
    local mapH = Config.MAP_HEIGHT or 30
    beast.x = math.max(1.5, math.min(mapW - 2.5, beast.x))
    beast.y = math.max(1.5, math.min(mapH - 2.5, beast.y))
end

function BeastAI.distTo(beast, px, py)
    local dx = beast.x - px
    local dy = beast.y - py
    return math.sqrt(dx * dx + dy * dy)
end

function BeastAI.randomNearby(beast, map, radius)
    local mapW = Config.MAP_WIDTH or 20
    local mapH = Config.MAP_HEIGHT or 30
    for attempt = 1, 10 do
        local tx = beast.x + (math.random() - 0.5) * radius * 2
        local ty = beast.y + (math.random() - 0.5) * radius * 2
        tx = math.max(2, math.min(mapW - 3, tx))
        ty = math.max(2, math.min(mapH - 3, ty))
        if not map:isBlocked(math.floor(tx), math.floor(ty)) then
            return { x = tx, y = ty }
        end
    end
    return { x = beast.x, y = beast.y }
end

function BeastAI.getContactType(beast, playerX, playerY)
    local toPlayerAngle = math.atan2(playerY - beast.y, playerX - beast.x)
    local diff = toPlayerAngle - (beast.facing or 0)
    while diff > math.pi do diff = diff - math.pi * 2 end
    while diff < -math.pi do diff = diff + math.pi * 2 end
    local absDiff = math.abs(diff)
    if absDiff > math.pi * 2 / 3 then return "back"
    elseif absDiff > math.pi / 3 then return "side"
    else return "front" end
end

------------------------------------------------------------
-- 创建异兽实体
------------------------------------------------------------
function BeastAI.createBeast(beastData, x, y, quality)
    return {
        id = beastData.id,
        type = beastData.id,
        name = beastData.name,
        element = beastData.element,
        quality = quality or "R",
        x = x, y = y,
        halfW = (beastData.bodySize or 0.4) * 0.8,
        halfH = (beastData.bodySize or 0.4) * 0.8,
        facing = math.random() * math.pi * 2,
        aiState = (quality == "R") and "wander" or "hidden",
        idleTimer = 0,
        idleDuration = 2 + math.random() * 3,
        alertTimer = 0,
        wanderTarget = nil,
        ambushBonus = false,
        guardLowered = false,
        burstWindow = false,
        invisible = false,
        baseSpeed = beastData.baseSpeed or 1.5,
        bodySize = beastData.bodySize or 0.4,
        senseRange = beastData.senseRange or 3,
        petrifyTimer = 0,
        inkTimer = 0,
    }
end

return BeastAI
