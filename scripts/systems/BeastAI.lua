--- 异兽 AI 状态机 + 朝向系统 + 个性行为
--- 白泽凝视、风鸣隐形、水蛟水面加速、雷翼高速冲刺窗口
--- 墨鸦墨迹、石灵石化防御、土偶不逃跑
local CollisionSystem = require("systems.CollisionSystem")
local Config = require("Config")
local EventBus = require("systems.EventBus")
local CombatSystem = require("systems.CombatSystem")

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
    -- 战斗新状态
    WARN       = "warn",
    CHASE      = "chase",
    ATTACK     = "attack",
}

-- 品质额外感知加成（叠加到异兽自身 senseRange 上）
BeastAI.QUALITY_SENSE_BONUS = { R = 0, SR = 1, SSR = 2 }

------------------------------------------------------------
-- 获取实际战斗类型（考虑品质变体）
------------------------------------------------------------
function BeastAI.getCombatType(beast)
    if beast.combatTypeSsr and beast.quality == "SSR" then
        return beast.combatTypeSsr
    end
    return beast.combatType or "passive"
end

------------------------------------------------------------
-- 攻击定义表
-- 每个攻击: { name, damage, range, warmup(预警), cooldown, effect, qualityMin }
------------------------------------------------------------
BeastAI.ATTACK_DEFS = {
    -- 001 玄狐
    ["001"] = {
        { name = "火尾横扫",   damage = 1, range = 2.5, warmup = 0.5, cooldown = 4.0, arc = 90 },
        { name = "三尾刺",     damage = 2, range = 2.0, warmup = 0.0, cooldown = 0, qualityMin = "SSR",
          effect = { debuff = "burn", duration = 1.0 } },
    },
    -- 002 噬天
    ["002"] = {
        { name = "暗影撞击",   damage = 2, range = 2.0, warmup = 0.3, cooldown = 5.0,
          effect = { knockback = 1.0 } },
        { name = "光吞噬",     damage = 1, range = 99, warmup = 0, cooldown = 0, qualityMin = "SR",
          trigger = "chaseTime", triggerVal = 10,
          effect = { visionShrink = 1.5, duration = 5.0 } },
        { name = "深渊吞噬",   damage = 3, range = 1.0, warmup = 0, cooldown = 0, qualityMin = "SSR",
          trigger = "chance", triggerVal = 0.3, backstabAfter = 1.5 },
    },
    -- 003 雷翼
    ["003"] = {
        { name = "雷击俯冲",   damage = 1, range = 99, warmup = 0.7, cooldown = 4.0,
          aoeType = "line" },
        { name = "电弧连击",   damage = 1, range = 1.0, warmup = 0, cooldown = 0, qualityMin = "SR",
          trigger = "onHit" },
        { name = "雷暴核心",   damage = 2, range = 99, warmup = 3.0, cooldown = 0, qualityMin = "SSR",
          trigger = "chaseTime", triggerVal = 8, backstabAfter = 1.5 },
    },
    -- 005 石灵
    ["005"] = {
        { name = "飞石",       damage = 1, range = 5.0, warmup = 0.4, cooldown = 4.0,
          aoeType = "line" },
        { name = "震地",       damage = 2, range = 1.5, warmup = 0.6, cooldown = 6.0, qualityMin = "SR",
          aoeType = "circle", aoeRadius = 2.0 },
        { name = "石化气息",   damage = 0, range = 99, warmup = 0, cooldown = 0, qualityMin = "SSR",
          trigger = "onHit", effect = { debuff = "petrify", duration = 3.0 } },
    },
    -- 006 水蛟
    ["006"] = {
        { name = "水流喷射",   damage = 1, range = 3.0, warmup = 0.5, cooldown = 4.0,
          aoeType = "line", effect = { noSprint = 2.0 } },
        { name = "旋涡拖拽",   damage = 1, range = 0.5, warmup = 0, cooldown = 6.0, qualityMin = "SR",
          trigger = "nearWater" },
        { name = "龙吼",       damage = 2, range = 3.0, warmup = 0.5, cooldown = 8.0, qualityMin = "SSR",
          trigger = "hpBelow50", aoeType = "circle", aoeRadius = 3.0 },
    },
    -- 007 风鸣
    ["007"] = {
        { name = "风刃突袭",   damage = 1, range = 1.5, warmup = 0.0, cooldown = 0,
          backstabAfter = 0.5 },
        { name = "风压推退",   damage = 1, range = 2.0, warmup = 0, cooldown = 0, qualityMin = "SR",
          trigger = "afterAmbush", effect = { pushback = 3.0 } },
        { name = "隐遁撕裂",   damage = 2, range = 1.0, warmup = 0, cooldown = 0, qualityMin = "SSR",
          trigger = "backAttack", effect = { debuff = "dizzy", duration = 2.0 } },
    },
    -- 008 土偶
    ["008"] = {
        { name = "泥掌拍击",   damage = 2, range = 1.0, warmup = 1.0, cooldown = 5.0 },
        { name = "泥团投掷",   damage = 1, range = 4.0, warmup = 0.5, cooldown = 4.0,
          aoeType = "circle", aoeRadius = 1.0,
          effect = { debuff = "sticky", duration = 5.0 } },
    },
    -- 010 墨鸦
    ["010"] = {
        { name = "墨爪掠过",   damage = 1, range = 1.5, warmup = 0.0, cooldown = 3.0 },
        { name = "墨迹喷射",   damage = 0, range = 4.0, warmup = 0, cooldown = 5.0,
          effect = { debuff = "ink", duration = 20.0 } },
        { name = "群鸦突袭",   damage = 2, range = 3.0, warmup = 0, cooldown = 0, qualityMin = "SSR",
          trigger = "chaseTime", triggerVal = 15, backstabAfter = 3.0 },
    },
}

-- 品质排序用于 qualityMin 判断
local QUALITY_RANK = { R = 1, SR = 2, SSR = 3 }

function BeastAI.meetsQuality(beast, qualityMin)
    if not qualityMin then return true end
    return (QUALITY_RANK[beast.quality] or 1) >= (QUALITY_RANK[qualityMin] or 1)
end

--- 获取异兽当前可用的主攻击（排除触发型，按品质过滤）
function BeastAI.getPrimaryAttack(beast)
    local defs = BeastAI.ATTACK_DEFS[beast.id]
    if not defs then return nil end
    for _, atk in ipairs(defs) do
        if BeastAI.meetsQuality(beast, atk.qualityMin) and not atk.trigger and atk.cooldown > 0 then
            return atk
        end
    end
    -- 如果全都是触发型，取第一个满足品质的
    for _, atk in ipairs(defs) do
        if BeastAI.meetsQuality(beast, atk.qualityMin) then
            return atk
        end
    end
    return nil
end

--- 获取特定触发类型的攻击
function BeastAI.getTriggeredAttack(beast, triggerType)
    local defs = BeastAI.ATTACK_DEFS[beast.id]
    if not defs then return nil end
    for _, atk in ipairs(defs) do
        if atk.trigger == triggerType and BeastAI.meetsQuality(beast, atk.qualityMin) then
            return atk
        end
    end
    return nil
end

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

    -- 背刺窗口倒计时
    if beast.backstabWindow and beast.backstabWindow > 0 then
        beast.backstabWindow = beast.backstabWindow - dt
        if beast.backstabWindow <= 0 then
            beast.backstabWindow = 0
        end
    end

    -- 白泽庇护光晕攻击力减弱倒计时
    if beast.atkReductionTimer and beast.atkReductionTimer > 0 then
        beast.atkReductionTimer = beast.atkReductionTimer - dt
        if beast.atkReductionTimer <= 0 then
            beast.atkReductionTimer = 0
            beast.atkReduction = nil
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

    -- 眩晕/冻结：跳过所有行动
    if state == "stunned" or state == "frozen" then
        return
    end

    -- 封印阵效果：检查是否在阵内
    local SkillSystem = require("systems.SkillSystem")
    local zoneEffect = SkillSystem.getZoneEffect(beast.x, beast.y)
    if zoneEffect then
        beast.inZone = true
        beast.zoneSpeedMul = zoneEffect.speedMul or 0.60
        beast.zonePerceptionReduce = zoneEffect.perceptionReduce or 2
    else
        beast.inZone = false
        beast.zoneSpeedMul = nil
        beast.zonePerceptionReduce = nil
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
        -- 减速效果（技能/封印阵）
        if beast.slowMul and beast.slowTimer and beast.slowTimer > 0 then
            speed = speed * beast.slowMul
        end
        if beast.zoneSpeedMul then
            speed = speed * beast.zoneSpeedMul
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
        -- 封印阵感知削减
        if beast.zonePerceptionReduce then
            senseRange = senseRange - beast.zonePerceptionReduce
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
        local cType = BeastAI.getCombatType(beast)

        if dist < 2 then
            if cType == "passive" then
                beast.aiState = "flee"
            elseif cType == "territorial" then
                -- 领地型：进入警告
                beast.aiState = "warn"
                beast.warnTimer = 0
                EventBus.emit("beast_warn", { beast = beast })
            elseif cType == "aggressive" then
                -- 主动型：进入追击
                beast.aiState = "chase"
                beast.chaseTimer = 0
                beast.chaseTriggered = false
                beast.attackCooldown = 1.0
            elseif cType == "ambush" then
                -- 伏击型被发现后按主动型处理
                beast.aiState = "chase"
                beast.chaseTimer = 0
                beast.chaseTriggered = false
                beast.attackCooldown = 1.0
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
        -- 雷翼停止1.5秒（追击窗口），之后进入chase追击
        beast.burstStopTimer = (beast.burstStopTimer or 0) + dt
        beast.burstWindow = true
        beast.backstabWindow = math.max(beast.backstabWindow or 0, 1.5 - beast.burstStopTimer)
        if beast.burstStopTimer >= 1.5 then
            beast.aiState = "chase"
            beast.burstStopTimer = 0
            beast.burstWindow = false
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 2.0
        end

    elseif state == "petrified" then
        -- 石灵石化防御：不可操作，等待timer清零（由上方petrifyTimer处理）

    elseif state == "warn" then
        -- 领地型：警告1.5秒，显示符文；玩家撤出领地→wander，否则→attack
        beast.warnTimer = (beast.warnTimer or 0) + dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        local dist = BeastAI.distTo(beast, playerX, playerY)
        local tRadius = beast.territoryRadius or 5

        -- 判断玩家是否在领地外（相对领地中心）
        local tdx = playerX - (beast.territoryX or beast.x)
        local tdy = playerY - (beast.territoryY or beast.y)
        local tDist = math.sqrt(tdx * tdx + tdy * tdy)

        if tDist > tRadius then
            -- 玩家撤出领地
            beast.aiState = "wander"
            beast.warnTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        elseif beast.warnTimer >= 1.5 then
            -- 警告时间到，发动攻击
            beast.aiState = "attack"
            beast.warnTimer = 0
            beast.attackCooldown = 0
            beast.attackTimer = 0
            beast.attackState = nil
        end

    elseif state == "chase" then
        -- 主动型/伏击型：追击玩家（速度×1.3），周期攻击
        beast.chaseTimer = (beast.chaseTimer or 0) + dt
        beast.attackCooldown = (beast.attackCooldown or 0) - dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

        local dist = BeastAI.distTo(beast, playerX, playerY)

        -- 距离>12放弃追击
        if dist > 12 then
            beast.aiState = "wander"
            beast.chaseTimer = 0
            beast.attackCooldown = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        else
            -- 追击移动
            local speed = (beast.baseSpeed or 1.5) * 1.3
            if beast.id == "006" then speed = speed + BeastAI.getWaterBonus(beast, map) end
            -- 减速效果（技能/封印阵）
            if beast.slowMul and beast.slowTimer and beast.slowTimer > 0 then
                speed = speed * beast.slowMul
            end
            if beast.zoneSpeedMul then
                speed = speed * beast.zoneSpeedMul
            end
            local target = { x = playerX, y = playerY }
            BeastAI.moveToward(beast, target, dt, speed, map)

            -- 检查触发型攻击（chaseTime型）
            local chaseAtk = BeastAI.getTriggeredAttack(beast, "chaseTime")
            if chaseAtk and beast.chaseTimer >= (chaseAtk.triggerVal or 99) and not beast.chaseTriggered then
                beast.chaseTriggered = true
                beast.aiState = "attack"
                beast.attackState = chaseAtk.name
                beast.attackTimer = chaseAtk.warmup or 0
                beast.currentAttack = chaseAtk
            -- 概率型触发攻击（噬天深渊吞噬）
            elseif dist <= 1.0 then
                local chanceAtk = BeastAI.getTriggeredAttack(beast, "chance")
                if chanceAtk and math.random() < (chanceAtk.triggerVal or 0) and beast.attackCooldown <= 0 then
                    beast.aiState = "attack"
                    beast.attackState = chanceAtk.name
                    beast.attackTimer = chanceAtk.warmup or 0
                    beast.currentAttack = chanceAtk
                    beast.attackCooldown = 3.0
                end
            end

            -- 常规攻击冷却到了
            if beast.aiState == "chase" and beast.attackCooldown <= 0 then
                local primaryAtk = BeastAI.getPrimaryAttack(beast)
                if primaryAtk and dist <= (primaryAtk.range or 2.0) then
                    beast.aiState = "attack"
                    beast.attackState = primaryAtk.name
                    beast.attackTimer = primaryAtk.warmup or 0
                    beast.currentAttack = primaryAtk
                end
            end
        end

    elseif state == "attack" then
        -- 攻击执行：warmup(预警)阶段→命中判定→硬直/背刺窗口
        beast.attackTimer = (beast.attackTimer or 0) - dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

        if beast.attackTimer <= 0 then
            -- 预警结束，执行攻击
            local atk = beast.currentAttack or BeastAI.getPrimaryAttack(beast)
            if atk then
                local dist = BeastAI.distTo(beast, playerX, playerY)
                local hit = false

                -- 命中判定：根据攻击类型判断
                if atk.aoeType == "circle" then
                    hit = dist <= (atk.aoeRadius or 2.0)
                elseif atk.arc then
                    -- 扇形判断
                    if dist <= (atk.range or 2.5) then
                        local toPlayer = math.atan2(playerY - beast.y, playerX - beast.x)
                        local diff = toPlayer - (beast.facing or 0)
                        while diff > math.pi do diff = diff - math.pi * 2 end
                        while diff < -math.pi do diff = diff + math.pi * 2 end
                        hit = math.abs(diff) <= math.rad(atk.arc / 2)
                    end
                else
                    hit = dist <= (atk.range or 2.0)
                end

                if hit and atk.damage > 0 then
                    local finalDmg = atk.damage
                    -- 白泽庇护光晕：攻击力降低
                    if beast.atkReduction and beast.atkReductionTimer and beast.atkReductionTimer > 0 then
                        finalDmg = math.max(1, math.floor(finalDmg * (1 - beast.atkReduction)))
                    end
                    CombatSystem.takeDamage(finalDmg, "beast")
                    EventBus.emit("beast_attack_hit", {
                        beast = beast, attack = atk.name, damage = atk.damage,
                    })
                    -- 命中触发的附加攻击（onHit型）
                    local onHitAtk = BeastAI.getTriggeredAttack(beast, "onHit")
                    if onHitAtk then
                        if onHitAtk.damage > 0 then
                            CombatSystem.takeDamage(onHitAtk.damage, "beast")
                        end
                        if onHitAtk.effect and onHitAtk.effect.debuff then
                            CombatSystem.applyDebuff(onHitAtk.effect.debuff, onHitAtk.effect.duration)
                        end
                    end
                end

                -- 应用效果
                if hit and atk.effect then
                    if atk.effect.debuff then
                        CombatSystem.applyDebuff(atk.effect.debuff, atk.effect.duration)
                    end
                    if atk.effect.knockback then
                        EventBus.emit("player_knockback", {
                            fromX = beast.x, fromY = beast.y, dist = atk.effect.knockback,
                        })
                    end
                    if atk.effect.visionShrink then
                        EventBus.emit("vision_shrink", {
                            radius = atk.effect.visionShrink, duration = atk.effect.duration,
                        })
                    end
                end

                -- 攻击后处理：背刺窗口或返回chase/wander
                if atk.backstabAfter and atk.backstabAfter > 0 then
                    beast.backstabWindow = atk.backstabAfter
                end

                -- 设置攻击冷却
                local cd = atk.cooldown or 4.0
                if cd <= 0 then cd = 4.0 end
                beast.attackCooldown = cd
            end

            -- 攻击完毕，回到之前的行为
            local cType = BeastAI.getCombatType(beast)
            if cType == "territorial" then
                beast.aiState = "wander"
                beast.wanderTarget = { x = beast.territoryX or beast.x, y = beast.territoryY or beast.y }
            elseif cType == "aggressive" or cType == "ambush" then
                beast.aiState = "chase"
            else
                beast.aiState = "wander"
                beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
            end
            beast.attackState = nil
            beast.currentAttack = nil
            beast.attackTimer = 0
        end

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
-- 感知后的反应（基于战斗行为类型 + 个性化）
------------------------------------------------------------
function BeastAI.onSensed(beast, contactType, playerX, playerY, map)
    local beastId = beast.id
    local cType = BeastAI.getCombatType(beast)

    beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

    -- 白泽：特殊凝视（被动型但有独特机制）
    if beastId == "004" then
        if contactType == "front" or contactType == "side" then
            beast.aiState = "gaze"
            beast.gazePhase = "approach"
        end
        return
    end

    -- 雷翼：感知后进入高速冲刺（主动型但有独特burst行为，先burst再chase）
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
        else
            beast.aiState = "alert"
        end
        return
    end

    -- 根据战斗行为类型分发
    if cType == "passive" then
        -- 被动型：alert→flee
        if contactType == "front" or contactType == "side" then
            beast.aiState = "alert"
        end

    elseif cType == "territorial" then
        -- 领地型：alert→warn（封印阵内视为无威胁，不进入warn）
        if beast.inZone then
            -- 封印阵内：领地型不攻击
        elseif contactType == "front" then
            beast.aiState = "warn"
            beast.warnTimer = 0
            EventBus.emit("beast_warn", { beast = beast })
        elseif contactType == "side" then
            beast.aiState = "alert"
        end

    elseif cType == "aggressive" then
        -- 主动型：alert→chase
        if contactType == "front" or contactType == "side" then
            beast.aiState = "chase"
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 1.5  -- 首次追击1.5秒后才能攻击
        elseif contactType == "back" and beast.quality == "SSR" then
            -- SSR主动型背后被发现也会追击
            beast.aiState = "chase"
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 2.0
        end

    elseif cType == "ambush" then
        -- 伏击型：触发圈内立即攻击
        local dist = BeastAI.distTo(beast, playerX, playerY)
        -- 追迹流初学+：竹林中伏击触发圈缩小
        local ambushR = beast.ambushRange or 1.5
        local SchoolEffects = require("systems.SchoolEffects")
        local sEffect = SchoolEffects.get()
        local pTile = map and map:getTile(math.floor(playerX), math.floor(playerY))
        local pInBamboo = pTile and pTile.type == "bamboo"
        if sEffect and sEffect.ambushRadiusOverride and pInBamboo then
            ambushR = sEffect.ambushRadiusOverride
        end
        if dist <= ambushR then
            -- 伏击触发：立即攻击
            beast.invisible = false
            beast.aiState = "attack"
            beast.attackTimer = 0  -- 无预警
            local ambushAtk = BeastAI.getPrimaryAttack(beast)
            beast.currentAttack = ambushAtk
            beast.attackState = ambushAtk and ambushAtk.name or nil
            EventBus.emit("beast_ambush", { beast = beast })
        else
            -- 距离不够近，进入alert
            beast.aiState = "alert"
        end
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
-- 白泽庇护光晕（白泽凝视期间玩家被攻击时触发）
------------------------------------------------------------
function BeastAI.triggerBaizeProtection(beast, allBeasts, playerX, playerY)
    if beast.id ~= "004" then return false end
    if beast.aiState ~= "gaze" then return false end

    -- 降低周围2格内异兽攻击力50%持续3秒
    for _, other in ipairs(allBeasts) do
        if other ~= beast and other.aiState ~= "captured" then
            local dx = other.x - beast.x
            local dy = other.y - beast.y
            if dx * dx + dy * dy <= 4 then -- 2格范围
                other.atkReduction = 0.50
                other.atkReductionTimer = 3.0
            end
        end
    end

    -- 白泽庇护后逃跑
    beast.aiState = "flee"
    beast.gazePhase = nil
    beast.gazeWatchTimer = nil

    EventBus.emit("baize_protection", { beast = beast })
    return true
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
    local beast = {
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
        -- 战斗行为字段
        combatType = beastData.combatType or "passive",
        combatTypeSsr = beastData.combatTypeSsr,
        territoryRadius = beastData.territoryRadius or 5,
        ambushRange = beastData.ambushRange or 1.5,
        -- 领地原点（生成位置即领地中心）
        territoryX = x,
        territoryY = y,
        -- 战斗状态
        warnTimer = 0,
        chaseTimer = 0,
        attackCooldown = 0,
        attackState = nil,  -- 当前攻击动作名
        attackTimer = 0,    -- 攻击动画/硬直计时
        backstabWindow = 0, -- 背刺窗口剩余时间
    }
    -- 初始化异兽战斗HP
    CombatSystem.initBeastHP(beast)
    return beast
end

return BeastAI
