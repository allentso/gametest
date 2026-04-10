--- ExploreScreen - 探索主界面（核心玩法）
--- 6层渲染: 宣纸底→瓦片→实体→迷雾→HUD→模态叠层
local Config = require("Config")
local InkPalette = require("data.InkPalette")
local BeastData = require("data.BeastData")
local Camera = require("systems.Camera")
local ExploreMap = require("systems.ExploreMap")
local FogOfWar = require("systems.FogOfWar")
local Timer = require("systems.Timer")
local CollisionSystem = require("systems.CollisionSystem")
local VirtualJoystick = require("systems.VirtualJoystick")
local BeastAI = require("systems.BeastAI")
local TrackingSystem = require("systems.TrackingSystem")
local SuppressSystem = require("systems.SuppressSystem")
local CaptureSystem = require("systems.CaptureSystem")
local EvacuationSystem = require("systems.EvacuationSystem")
local SessionState = require("systems.SessionState")
local GameState = require("systems.GameState")
local EventBus = require("systems.EventBus")
local ScreenManager = require("systems.ScreenManager")
local CombatSystem = require("systems.CombatSystem")
local SkillSystem = require("systems.SkillSystem")
local TutorialSystem = require("systems.TutorialSystem")
local BrushStrokes = require("render.BrushStrokes")
local InkTileRenderer = require("render.InkTileRenderer")
local InkRenderer = require("render.InkRenderer")
local BeastRenderer = require("render.BeastRenderer")

-- 资源拼音→中文名映射
local RES_NAMES = {
    lingshi = "灵石", shouhun = "兽魂", tianjing = "天晶", lingyin = "灵印",
    traceAsh = "追迹灰", mirrorSand = "镇灵砂", soulCharm = "归魂符",
    beastEye = "兽瞳", sealEcho = "封印回响", busicao = "不死草",
}

local LoreData = require("data.LoreData")

local SchoolEffects = require("systems.SchoolEffects")

--- 获取当前流派效果表（nil 表示无效果）
local function getSchoolEffect()
    return SchoolEffects.get()
end

local ExploreScreen = {}
ExploreScreen.__index = ExploreScreen

function ExploreScreen.new(params)
    local self = setmetatable({}, ExploreScreen)
    self.isModal = false
    self.paused = false

    -- 玩家状态
    self.playerX = 0
    self.playerY = 0
    self.playerFacing = 0 -- 弧度
    self.playerMoving = false
    self.playerTrails = {} -- 行迹墨尘

    -- 地图与异兽
    self.map = nil
    self.beasts = {}
    self.activeBeast = nil -- 当前交互异兽

    -- 交互状态
    self.investigateTarget = nil
    self.investigateTimer = 0
    self.investigateDuration = 0
    self.collectTarget = nil

    -- 调查按钮状态
    self.interactType = nil -- "investigate"/"collect"/"suppress"/"evacuate"/nil
    self.interactTarget = nil

    -- Toast 消息
    self.toasts = {}

    -- 品质印章
    self.qualityStamp = nil -- nil/"SR"/"SSR"
    self.qualityStampAlpha = 0

    -- 震屏
    self.shakeTimer = 0
    self.shakeIntensity = 0

    -- 小地图
    self.minimapExpanded = false
    self.minimapBounds = nil

    -- 地面墨迹/毒迹系统
    self.inkPatches = {}
    -- 驱散法净化区域
    self.purifiedZones = {}

    -- 玩家静止计时（白泽凝视用）
    self.playerStillTimer = 0

    -- 紧急逃脱
    self.emergencyEscapeAvailable = false

    return self
end

function ExploreScreen:onEnter()
    -- SessionState.reset() 已在 PrepareScreen 出发时调用，此处不再重复

    -- 初始化地图
    self.map = ExploreMap.new()
    self.map:generate()

    -- 初始化迷雾
    FogOfWar.init(Config.MAP_WIDTH, Config.MAP_HEIGHT)

    -- 初始化战斗系统
    CombatSystem.reset()

    -- 初始化计时器
    Timer.reset(Config.GAME_DURATION)

    -- 初始化追踪
    TrackingSystem.reset()

    -- 初始化撤离
    EvacuationSystem.init(self.map)

    -- 出生点
    self.playerX = self.map.spawnPoint.x
    self.playerY = self.map.spawnPoint.y

    -- 相机初始位置
    Camera.x = self.playerX
    Camera.y = self.playerY

    -- 生成 R 级异兽（自然游荡）
    self:spawnInitialBeasts()

    -- 注册事件
    EventBus.on("beast_spawn_request", function(quality)
        self:spawnTrackedBeast(quality)
    end, self)

    EventBus.on("suppress_result", function(result)
        self:onSuppressResult(result)
    end, self)

    EventBus.on("beast_captured", function(contract, quality)
        SessionState.addContract(contract)
        TutorialSystem.checkTrigger("captured")
    end, self)

    EventBus.on("capture_failed", function(beast)
        self:addToast("捕获失败...")
        beast.aiState = "flee"
    end, self)

    EventBus.on("evacuation_complete", function()
        self:onEvacuationComplete()
    end, self)

    EventBus.on("evacuation_result", function(success, lostContracts)
        self:onEvacuationResult(success, lostContracts)
    end, self)

    -- 战斗系统事件
    EventBus.on("spirit_collapse_start", function(data)
        self:addToast("灵气溃散！")
        self.shakeTimer = 1.0
        self.shakeIntensity = 4
    end, self)

    EventBus.on("spirit_collapse_end", function()
        self:onSpiritCollapseEnd()
    end, self)

    EventBus.on("fusufu_triggered", function(data)
        self:addToast("复苏符生效！恢复" .. data.healed .. "滴灵气")
        self.shakeTimer = 0.5
        self.shakeIntensity = 2
    end, self)

    EventBus.on("player_damaged", function(data)
        if data.source ~= "miasma" then
            self.shakeTimer = 0.2
            self.shakeIntensity = 2
        end
        -- 白泽庇护光晕：凝视期间玩家被异兽攻击触发
        if data.source == "beast" then
            for _, beast in ipairs(self.beasts or {}) do
                if beast.id == "004" and beast.aiState == "gaze" then
                    BeastAI.triggerBaizeProtection(beast, self.beasts, self.playerX, self.playerY)
                    break
                end
            end
        end
    end, self)

    EventBus.on("baize_protection", function(data)
        self:addToast("白泽发出庇护光晕！周围异兽攻击力降低")
        self.shakeTimer = 0.3
        self.shakeIntensity = 1
    end, self)

    EventBus.on("ink_patch_created", function(patch)
        table.insert(self.inkPatches, {
            x = patch.x, y = patch.y,
            life = patch.duration, maxLife = patch.duration,
        })
    end, self)

    EventBus.on("habit_deduced", function()
        local nearestBeast = self:findNearestActiveBeast()
        if nearestBeast then
            local qx = nearestBeast.x < Config.MAP_WIDTH * 0.5 and "西" or "东"
            local qy = nearestBeast.y > Config.MAP_HEIGHT * 0.5 and "北" or "南"
            self:addToast("习性推断：异兽活动于" .. qy .. qx .. "象限")
        else
            self:addToast("习性推断完成，但未锁定方位")
        end
    end, self)

    -- 战斗事件
    EventBus.on("beast_attack_hit", function(data)
        self:addToast(data.beast.name .. "发动" .. data.attack .. "！-" .. data.damage .. "滴")
        self.shakeTimer = 0.3
        self.shakeIntensity = 3
        -- TODO Phase 2: 特殊异兽受击反应
    end, self)

    EventBus.on("beast_warn", function(data)
        self:addToast(data.beast.name .. "发出警告！尽快后退！")
    end, self)

    EventBus.on("beast_ambush", function(data)
        self:addToast(data.beast.name .. "伏击现身！")
        self.shakeTimer = 0.4
        self.shakeIntensity = 4
    end, self)

    EventBus.on("beast_weakened", function(data)
        self:addToast(data.beast.name .. "进入虚弱状态！封灵加成+15%")
    end, self)

    EventBus.on("player_knockback", function(data)
        -- 击退：从攻击源反方向推1格
        local angle = math.atan2(self.playerY - data.fromY, self.playerX - data.fromX)
        local kd = data.dist or 1.0
        self.playerX = self.playerX + math.cos(angle) * kd
        self.playerY = self.playerY + math.sin(angle) * kd
        -- 边界限制
        self.playerX = math.max(1.5, math.min(Config.MAP_WIDTH - 2.5, self.playerX))
        self.playerY = math.max(1.5, math.min(Config.MAP_HEIGHT - 2.5, self.playerY))
    end, self)

    EventBus.on("vision_shrink", function(data)
        -- 视野收缩效果（烛龙昼夜之瞳等）
        self.visionShrinkRadius = data.radius or 1.5
        self.visionShrinkTimer = data.duration or 5.0
    end, self)

    -- 流派追迹大成：SSR线索需求-1 + 玄采概率+10%
    local effect = getSchoolEffect()
    if effect and effect.ssrReduce then
        TrackingSystem.ssrReduceBonus = effect.ssrReduce
    end
    if effect and effect.xuancaiBonus then
        TrackingSystem.schoolXuancaiBonus = effect.xuancaiBonus
    end

    -- 流派重试标记（压制大成可重试1次）
    self.schoolRetryUsed = false

    -- 灵境传说卡片
    self.realmLegend = nil
    self.realmLegendAlpha = 0
    self.realmLegendDismissed = false
    local biome = SessionState.selectedBiome
    if biome then
        local legend = LoreData.getRealmLegend(biome)
        if legend then
            self.realmLegend = legend
        end
    end

    -- 迷雾残图：开局揭示25%地图
    if SessionState.hasItem("fogMap") then
        FogOfWar.revealRandom(0.25)
        self:addToast("迷雾残图生效：已探索25%区域")
        self.fogMapUsed = true
    else
        self.fogMapUsed = false
    end

    -- 疾风符初始化
    self.rushWardTimer = 0
    self.rushWardActive = false

    -- 兽目珠初始化
    self.beastEyeTimer = 0

    -- 恢复道具施法状态
    self.recoveryUsing = nil

    -- 背刺技能初始化
    SkillSystem.initSession(SessionState.selectedSkill)

    -- 特殊道具 HUD 按钮状态
    self.itemButtons = {}

    -- 技能事件监听
    EventBus.on("skill_hit", function(data)
        local desc = data.name
        if data.isBackstab then desc = "【背刺】" .. desc end
        if data.effectDesc then desc = desc .. "：" .. data.effectDesc end
        self:addToast(desc)
    end, self)
    EventBus.on("skill_fail", function(data)
        if data.reason == "uses_depleted" then
            self:addToast("技能次数已用完")
        elseif data.reason == "no_target" then
            self:addToast("范围内无目标")
        elseif data.reason == "cooldown" then
            self:addToast("技能冷却中...")
        elseif data.reason == "collapsed" then
            self:addToast("溃散状态无法使用技能")
        end
    end, self)
    EventBus.on("skill_zone_placed", function(data)
        self:addToast(data.name .. "已布置")
    end, self)
    EventBus.on("skill_explosion", function(data)
        self.shakeTimer = 0.3
        self.shakeIntensity = 4
    end, self)
    EventBus.on("player_debuffs_cleared", function(data)
        CombatSystem.clearAllDebuffs()
        self:addToast("身上异状已驱散")
    end, self)
    EventBus.on("ink_cleared", function(data)
        local cx, cy, r = data.x, data.y, data.radius
        for i = #self.inkPatches, 1, -1 do
            local p = self.inkPatches[i]
            local dx, dy = p.x - cx, p.y - cy
            if dx * dx + dy * dy <= r * r then
                table.remove(self.inkPatches, i)
            end
        end
    end, self)
    EventBus.on("miasma_purified", function(data)
        table.insert(self.purifiedZones, {
            x = data.x, y = data.y,
            radius = data.radius,
            timer = data.duration,
        })
    end, self)
    EventBus.on("beast_stunned", function(data)
        local beast = data.beast
        if beast and not beast.ccImmune and not beast.skillImmune then
            beast.stunTimer = data.duration
            beast.prevAiState = beast.aiState
            beast.aiState = "stunned"
        end
    end, self)
    EventBus.on("beast_slowed", function(data)
        local beast = data.beast
        if beast and not beast.ccImmune and not beast.skillImmune then
            beast.slowTimer = data.duration
            beast.slowMul = data.speedMul
        end
    end, self)
    EventBus.on("beast_frozen", function(data)
        local beast = data.beast
        if beast and not beast.ccImmune and not beast.skillImmune then
            beast.freezeTimer = data.duration
            beast.prevAiState = beast.aiState
            beast.aiState = "frozen"
        end
    end, self)
    EventBus.on("beast_interrupted", function(data)
        local beast = data.beast
        if beast then
            beast.attackState = nil
            beast.attackTimer = 0
        end
    end, self)
    EventBus.on("beast_abandon_chase", function(data)
        local beast = data.beast
        if beast then
            beast.aiState = "wander"
            beast.chaseTimer = 0
        end
    end, self)
    EventBus.on("beast_revealed", function(data)
        local beast = data.beast
        if beast then
            beast.revealed = true
            self:addToast("伏击异兽已暴露！")
        end
    end, self)

    -- 新手引导
    TutorialSystem.start()
    TutorialSystem.checkTrigger("enter_map")
end

function ExploreScreen:onExit()
    EventBus.off(nil, self)
    VirtualJoystick.active = false
end

function ExploreScreen:onPause()
    self.paused = true
end

function ExploreScreen:onResume()
    self.paused = false
    if self.pendingSuppressRetry and self.activeBeast then
        self.pendingSuppressRetry = false
        local beast = self.activeBeast
        local hasMirrorSand = SessionState.hasItem("mirrorSand")
        if hasMirrorSand then
            SessionState.addItem("mirrorSand", -1)
        end
        SuppressSystem.start(beast, hasMirrorSand)
        local sEffect = getSchoolEffect()
        if sEffect then
            if sEffect.qteSpeedMul then
                SuppressSystem.state.speed = SuppressSystem.state.speed * sEffect.qteSpeedMul
            end
            if sEffect.qteZoneMul then
                local z = SuppressSystem.state.targetZone
                local center = (z[1] + z[2]) * 0.5
                local halfW = (z[2] - z[1]) * 0.5 * sEffect.qteZoneMul
                z[1] = math.max(0.05, center - halfW)
                z[2] = math.min(0.95, center + halfW)
            end
        end
        local SuppressOverlay = require("screens.SuppressOverlay")
        ScreenManager.push(SuppressOverlay, { beast = beast })
    else
        self.pendingSuppressRetry = false
    end
end

------------------------------------------------------------
-- 异兽生成
------------------------------------------------------------

function ExploreScreen:spawnInitialBeasts()
    local count = 3 + math.random(0, 2)
    local biome = SessionState.selectedBiome
    for i = 1, count do
        local beastInfo = biome
            and BeastData.getRandomForBiome(biome)
            or BeastData.getRandom()
        local x, y = self:findOpenPosition(4, self.map.height - 2)
        if x then
            local beast = BeastAI.createBeast(beastInfo, x, y, "R")
            table.insert(self.beasts, beast)
        end
    end
end

function ExploreScreen:spawnTrackedBeast(quality)
    local biome = SessionState.selectedBiome
    local beastInfo = biome
        and BeastData.getRandomForBiome(biome, quality)
        or BeastData.getRandom()
    -- 在玩家周围 6-10 格找一个可通行位置
    local tx, ty
    for _ = 1, 20 do
        local angle = math.random() * math.pi * 2
        local dist = 6 + math.random() * 4
        local cx = math.floor(self.playerX + math.cos(angle) * dist)
        local cy = math.floor(self.playerY + math.sin(angle) * dist)
        cx = math.max(2, math.min(Config.MAP_WIDTH - 3, cx))
        cy = math.max(2, math.min(Config.MAP_HEIGHT - 3, cy))
        if not self.map:isBlocked(cx, cy) and not self.map:isOccupied(cx, cy) then
            tx, ty = cx, cy
            break
        end
    end
    if not tx then
        tx = math.max(2, math.min(Config.MAP_WIDTH - 3, math.floor(self.playerX + 6)))
        ty = math.max(2, math.min(Config.MAP_HEIGHT - 3, math.floor(self.playerY + 6)))
    end

    local beast = BeastAI.createBeast(beastInfo, tx, ty, quality)
    beast.aiState = "wander"
    table.insert(self.beasts, beast)
    self:addToast(quality .. "级异兽出现！")
    TutorialSystem.checkTrigger("beast_spawned")
end

function ExploreScreen:findOpenPosition(minY, maxY)
    for _ = 1, 50 do
        local x = math.random(3, Config.MAP_WIDTH - 3)
        local y = math.random(minY, maxY)
        if not self.map:isBlocked(x, y) and not self.map:isOccupied(x, y) then
            -- 与已有异兽保持距离
            local tooClose = false
            for _, beast in ipairs(self.beasts) do
                local dx = beast.x - x
                local dy = beast.y - y
                if dx * dx + dy * dy < 9 then
                    tooClose = true
                    break
                end
            end
            -- 与玩家保持距离
            if not tooClose then
                local dx = self.playerX - x
                local dy = self.playerY - y
                if dx * dx + dy * dy < 16 then
                    tooClose = true
                end
            end
            if not tooClose then
                return x, y
            end
        end
    end
    return nil, nil
end

------------------------------------------------------------
-- 更新
------------------------------------------------------------

function ExploreScreen:update(dt)
    if self.paused then return end

    -- 计时器
    Timer.update(dt)
    if Timer.phase == "collapsed" then
        -- 时间到，强制结算（失败）
        self:forceEnd()
        return
    end

    -- 灾变吞噬
    local collapseProgress = Timer.getCollapseProgress()
    if collapseProgress > 0 then
        FogOfWar.collapseEdge(collapseProgress)
    end

    -- 玩家移动
    self:updatePlayerMovement(dt)

    -- 玩家静止计时（白泽凝视等）
    if self.playerMoving then
        self.playerStillTimer = 0
    else
        self.playerStillTimer = self.playerStillTimer + dt
    end

    -- 线索调查计时器
    if self.investigateTarget then
        if self.playerMoving then
            -- 移动时取消调查
            self.investigateTarget = nil
            self.investigateTimer = 0
            self:addToast("调查中断")
        else
            self.investigateTimer = self.investigateTimer + dt
            if self.investigateTimer >= self.investigateDuration then
                self:completeInvestigation()
            end
        end
    end

    -- 墨迹更新
    for i = #self.inkPatches, 1, -1 do
        self.inkPatches[i].life = self.inkPatches[i].life - dt
        if self.inkPatches[i].life <= 0 then
            table.remove(self.inkPatches, i)
        end
    end

    -- 净化区域倒计时
    for i = #self.purifiedZones, 1, -1 do
        self.purifiedZones[i].timer = self.purifiedZones[i].timer - dt
        if self.purifiedZones[i].timer <= 0 then
            table.remove(self.purifiedZones, i)
        end
    end

    -- 迷雾更新（竹林中视野缩减至3格，追迹流派+视距）
    local visionRadius = Config.VISION_RADIUS
    if self.playerInBamboo then visionRadius = 3.0 end
    -- TODO Phase 2: 封印被动视野加成
    local effect = getSchoolEffect()
    if effect and effect.clueVision then
        visionRadius = visionRadius + effect.clueVision
    end
    -- 地面墨迹/毒迹区域降低视野
    for _, patch in ipairs(self.inkPatches) do
        local pdx = self.playerX - patch.x
        local pdy = self.playerY - patch.y
        if pdx * pdx + pdy * pdy < 4 then
            visionRadius = math.min(visionRadius, 1.0)
            break
        end
    end
    -- 战斗系统视野乘数（墨迹debuff）
    visionRadius = visionRadius * CombatSystem.getVisionMultiplier()
    -- 视野收缩效果（烛龙昼夜之瞳等）
    if self.visionShrinkTimer and self.visionShrinkTimer > 0 then
        self.visionShrinkTimer = self.visionShrinkTimer - dt
        visionRadius = math.min(visionRadius, self.visionShrinkRadius or 1.5)
    end
    -- 溃散状态视野强制收缩
    if CombatSystem.collapsed then
        visionRadius = math.min(visionRadius, CombatSystem.COLLAPSE_VISION)
    end
    FogOfWar.update(self.playerX, self.playerY, visionRadius)

    -- 相机跟随
    Camera.follow(self.playerX, self.playerY, dt)

    -- collapse阶段全图异兽进入panic
    if Timer.phase == "collapse" and not self.panicTriggered then
        self.panicTriggered = true
        BeastAI.panicAll(self.beasts)
    end

    -- 异兽 AI（传递竹林隐蔽状态）
    local tileX = math.floor(self.playerX)
    local tileY = math.floor(self.playerY)
    local curTile = self.map:getTile(tileX, tileY)
    local aiOptions = {
        playerInBamboo = self.playerInBamboo,
        playerInDanger = curTile and curTile.type == "danger",
        playerMoving = self.playerMoving,
    }
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "suppress" then
            BeastAI.update(beast, dt, self.playerX, self.playerY, self.map, aiOptions)
        end
    end

    -- 异兽虚弱状态更新
    for _, beast in ipairs(self.beasts) do
        CombatSystem.updateBeastWeaken(beast, dt)
    end

    -- 撤离更新
    EvacuationSystem.update(dt, self.playerX, self.playerY)

    -- 交互检测
    self:updateInteraction()

    -- 行迹更新
    self:updateTrails(dt)

    -- Toast 更新
    self:updateToasts(dt)

    -- 震屏衰减
    if self.shakeTimer > 0 then
        self.shakeTimer = self.shakeTimer - dt
    end

    -- 品质印章更新
    self:updateQualityStamp(dt)

    -- 灵境传说卡片淡入淡出
    if self.realmLegend and not self.realmLegendDismissed then
        self.realmLegendAlpha = math.min(1, self.realmLegendAlpha + dt * 1.5)
    elseif self.realmLegendDismissed and self.realmLegendAlpha > 0 then
        self.realmLegendAlpha = math.max(0, self.realmLegendAlpha - dt * 2.0)
        if self.realmLegendAlpha <= 0 then
            self.realmLegend = nil
        end
    end

    -- 质量自动调节
    Config.autoAdjust(dt)
end

function ExploreScreen:updatePlayerMovement(dt)
    local dx, dy = VirtualJoystick.getMoveDirection()
    self.playerMoving = (math.abs(dx) > 0.01 or math.abs(dy) > 0.01)

    -- 检测玩家所在地形
    local tileX = math.floor(self.playerX)
    local tileY = math.floor(self.playerY)
    local currentTile = self.map:getTile(tileX, tileY)
    local tileType = currentTile and currentTile.type or "grass"

    -- 竹林隐蔽状态（供BeastAI使用）
    self.playerInBamboo = (tileType == "bamboo")

    -- 瘴气地形HP伤害（贪渊流派可减免；净化区域内免疫）
    local inMiasma = (tileType == "danger")
    if inMiasma then
        for _, zone in ipairs(self.purifiedZones) do
            local zdx, zdy = self.playerX - zone.x, self.playerY - zone.y
            if zdx * zdx + zdy * zdy <= zone.radius * zone.radius then
                inMiasma = false
                break
            end
        end
    end
    local greedEffect = getSchoolEffect()
    local miasmaImmune = greedEffect and greedEffect.dangerImmune or false
    local miasmaHalf = greedEffect and greedEffect.dangerDrainHalf or false
    CombatSystem.update(dt, Timer.phase or "explore", inMiasma, miasmaImmune, miasmaHalf)

    if self.playerMoving then
        local speed = Config.PLAYER_SPEED
        -- 小路地形移速+10%
        if tileType == "path" then
            speed = speed * 1.1
        end
        -- 疾风符加成
        if self.rushWardTimer and self.rushWardTimer > 0 then
            speed = speed * 1.3
        end
        -- TODO Phase 2: 封印被动水面移速加成
        -- 战斗系统速度乘数（debuff/溃散减速）
        speed = speed * CombatSystem.getSpeedMultiplier()

        -- 迷向debuff：随机偏转移动方向（±60°抖动）
        if CombatSystem.hasDebuff("dizzy") then
            local angle = math.atan2(dy, dx)
            local jitter = (math.random() - 0.5) * math.pi * 0.67  -- ±60°
            angle = angle + jitter
            local len = math.sqrt(dx * dx + dy * dy)
            dx = math.cos(angle) * len
            dy = math.sin(angle) * len
        end

        local moveX = dx * speed * dt
        local moveY = dy * speed * dt
        local proxy = { x = self.playerX, y = self.playerY, halfW = 0.3, halfH = 0.3 }
        CollisionSystem.tryMove(proxy, moveX, moveY, self.map)
        self.playerX = proxy.x
        self.playerY = proxy.y
        self.playerFacing = math.atan2(dy, dx)

        if math.random() < 0.3 then
            table.insert(self.playerTrails, {
                x = self.playerX, y = self.playerY,
                life = 0.3, maxLife = 0.3,
                alpha = 0.2 + math.random() * 0.1,
            })
        end

        if EvacuationSystem.evacuating then
            EvacuationSystem.cancel()
        end
    end

    -- 疾风符倒计时
    if self.rushWardTimer and self.rushWardTimer > 0 then
        self.rushWardTimer = self.rushWardTimer - dt
        if self.rushWardTimer <= 0 then
            self.rushWardTimer = 0
            self.rushWardActive = false
            self:addToast("疾风符效果已消散")
        end
    end

    -- 兽目珠倒计时
    if self.beastEyeTimer and self.beastEyeTimer > 0 then
        self.beastEyeTimer = self.beastEyeTimer - dt
        if self.beastEyeTimer <= 0 then
            self.beastEyeTimer = 0
            self:addToast("兽目珠灵光已消退")
        end
    end

    -- 背刺技能系统更新
    SkillSystem.update(dt)

    -- 异兽眩晕/冻结状态倒计时
    for _, beast in ipairs(self.beasts or {}) do
        if beast.stunTimer and beast.stunTimer > 0 then
            beast.stunTimer = beast.stunTimer - dt
            if beast.stunTimer <= 0 then
                beast.stunTimer = 0
                beast.aiState = beast.prevAiState or "wander"
                beast.prevAiState = nil
            end
        end
        if beast.freezeTimer and beast.freezeTimer > 0 then
            beast.freezeTimer = beast.freezeTimer - dt
            if beast.freezeTimer <= 0 then
                beast.freezeTimer = 0
                beast.aiState = beast.prevAiState or "wander"
                beast.prevAiState = nil
            end
        end
        if beast.slowTimer and beast.slowTimer > 0 then
            beast.slowTimer = beast.slowTimer - dt
            if beast.slowTimer <= 0 then
                beast.slowTimer = 0
                beast.slowMul = nil
            end
        end
    end

    -- 恢复道具施法倒计时
    if self.recoveryUsing then
        -- 打断检测：附近有异兽攻击或追击则取消
        local interrupted = false
        local effectEvac = getSchoolEffect()
        local allowInChase = effectEvac and effectEvac.recoveryCastMul
        for _, beast in ipairs(self.beasts or {}) do
            if beast.aiState == "attack" then
                local dist = math.sqrt((beast.x - self.playerX)^2 + (beast.y - self.playerY)^2)
                if dist < 4 then
                    interrupted = true
                    break
                end
            elseif beast.aiState == "chase" and not allowInChase then
                local dist = math.sqrt((beast.x - self.playerX)^2 + (beast.y - self.playerY)^2)
                if dist < 4 then
                    interrupted = true
                    break
                end
            end
        end
        if interrupted then
            -- 被打断：退还道具
            SessionState.addItem(self.recoveryUsing.itemId, 1)
            local name = (self.recoveryUsing.itemId == "lingquanWan") and "灵泉丸" or "绛珠露"
            self:addToast(name .. "使用被打断！")
            self.recoveryUsing = nil
        else
            self.recoveryUsing.timer = self.recoveryUsing.timer - dt
            if self.recoveryUsing.timer <= 0 then
                -- 施法完成：恢复HP
                CombatSystem.heal(self.recoveryUsing.healAmount)
                local name = (self.recoveryUsing.itemId == "lingquanWan") and "灵泉丸" or "绛珠露"
                self:addToast(name .. "生效，恢复" .. self.recoveryUsing.healAmount .. "点灵气")
                self.recoveryUsing = nil
            end
        end
    end

    self.playerX = math.max(1.5, math.min(Config.MAP_WIDTH - 2.5, self.playerX))
    self.playerY = math.max(1.5, math.min(Config.MAP_HEIGHT - 2.5, self.playerY))
end

function ExploreScreen:updateTrails(dt)
    for i = #self.playerTrails, 1, -1 do
        local t = self.playerTrails[i]
        t.life = t.life - dt
        if t.life <= 0 then
            table.remove(self.playerTrails, i)
        end
    end
end

function ExploreScreen:updateToasts(dt)
    for i = #self.toasts, 1, -1 do
        local t = self.toasts[i]
        t.life = t.life - dt
        if t.life <= 0 then
            table.remove(self.toasts, i)
        end
    end
end

function ExploreScreen:updateQualityStamp(dt)
    local target = nil
    local ssrThreshold = 5 - (TrackingSystem.ssrReduceBonus or 0)
    if TrackingSystem.clueCount >= ssrThreshold then
        target = "SSR"
    elseif TrackingSystem.clueCount >= 3 then
        target = "SR"
    end
    self.qualityStamp = target
    if target then
        self.qualityStampAlpha = math.min(0.3, self.qualityStampAlpha + dt * 0.5)
    else
        self.qualityStampAlpha = math.max(0, self.qualityStampAlpha - dt * 0.5)
    end
end

------------------------------------------------------------
-- 视线检测（Bresenham 步进，检查中间瓦片是否有障碍）
------------------------------------------------------------

function ExploreScreen:hasLineOfSight(x1, y1, x2, y2)
    local gx1, gy1 = math.floor(x1), math.floor(y1)
    local gx2, gy2 = math.floor(x2), math.floor(y2)
    local dx = math.abs(gx2 - gx1)
    local dy = math.abs(gy2 - gy1)
    local sx = gx1 < gx2 and 1 or -1
    local sy = gy1 < gy2 and 1 or -1
    local err = dx - dy
    local cx, cy = gx1, gy1
    while true do
        -- 跳过起终点，只检查中间瓦片
        if (cx ~= gx1 or cy ~= gy1) and (cx ~= gx2 or cy ~= gy2) then
            if self.map:isBlocked(cx, cy) then
                return false
            end
        end
        if cx == gx2 and cy == gy2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; cx = cx + sx end
        if e2 < dx then err = err + dx; cy = cy + sy end
    end
    return true
end

------------------------------------------------------------
-- 交互检测
------------------------------------------------------------

function ExploreScreen:updateInteraction()
    self.interactType = nil
    self.interactTarget = nil

    -- 优先级: 异兽压制 > 线索调查 > 资源收集 > 撤离
    -- 1. 检测附近异兽
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden"
           and beast.aiState ~= "burst" and beast.aiState ~= "suppress"
           and not beast.fakeDeath then
            local dist = BeastAI.distTo(beast, self.playerX, self.playerY)
            if dist < 1.2 and self:hasLineOfSight(self.playerX, self.playerY, beast.x, beast.y) then
                local contactType = BeastAI.getContactType(beast, self.playerX, self.playerY)
                if contactType == "back" then
                    beast.ambushBonus = true
                elseif beast.guardLowered then
                    beast.ambushBonus = true
                end
                self.interactType = "suppress"
                self.interactTarget = beast
                return
            end
        end
    end

    -- 2. 检测线索
    local clueRange = 1.2
    -- TODO Phase 2: 封印被动线索范围加成
    for _, clue in ipairs(self.map.clues) do
        if not clue.investigated then
            local dx = clue.x - self.playerX
            local dy = clue.y - self.playerY
            if math.sqrt(dx * dx + dy * dy) < clueRange then
                self.interactType = "investigate"
                self.interactTarget = clue
                return
            end
        end
    end

    -- 3. 检测资源
    for _, res in ipairs(self.map.resources) do
        if not res.collected then
            local dx = res.x - self.playerX
            local dy = res.y - self.playerY
            if math.sqrt(dx * dx + dy * dy) < 0.9 then
                self.interactType = "collect"
                self.interactTarget = res
                return
            end
        end
    end

    -- 4. 检测撤离点
    local nearPt, nearDist = EvacuationSystem.getNearestPoint(self.playerX, self.playerY)
    if nearPt and nearDist < 1.5 then
        self.interactType = "evacuate"
        self.interactTarget = nearPt
    end

    -- 5. 紧急逃脱条件：collapse阶段 + 距离最近撤离点 >8格
    self.emergencyEscapeAvailable = (Timer.phase == "collapse")
        and nearPt and nearDist > 8
end

------------------------------------------------------------
-- 交互执行
------------------------------------------------------------

function ExploreScreen:doInteract()
    if not self.interactType then return end

    if self.interactType == "suppress" then
        local beast = self.interactTarget
        beast.aiState = "suppress"
        self.activeBeast = beast
        local contactType = BeastAI.getContactType(beast, self.playerX, self.playerY)
        if contactType == "back" or beast.guardLowered then
            beast.ambushBonus = true
            SessionState.stats.ambushCount = (SessionState.stats.ambushCount or 0) + 1
            EventBus.emit("ambush_suppress")
        end
        local hasMirrorSand = SessionState.hasItem("mirrorSand")
        if hasMirrorSand then
            SessionState.addItem("mirrorSand", -1)
        end
        SuppressSystem.start(beast, hasMirrorSand)
        -- TODO Phase 2: 属性/地形 QTE 修正
        -- 流派压制效果：QTE速度/区域调整
        local sEffect = getSchoolEffect()
        if sEffect then
            if sEffect.qteSpeedMul then
                SuppressSystem.state.speed = SuppressSystem.state.speed * sEffect.qteSpeedMul
            end
            if sEffect.qteZoneMul then
                local z = SuppressSystem.state.targetZone
                local center = (z[1] + z[2]) * 0.5
                local halfW = (z[2] - z[1]) * 0.5 * sEffect.qteZoneMul
                z[1] = math.max(0.05, center - halfW)
                z[2] = math.min(0.95, center + halfW)
            end
        end
        local SuppressOverlay = require("screens.SuppressOverlay")
        ScreenManager.push(SuppressOverlay, { beast = beast })
        TutorialSystem.checkTrigger("suppress")

    elseif self.interactType == "investigate" then
        local clue = self.interactTarget
        if not self.investigateTarget then
            -- 开始调查：启动计时器
            local hasTraceAsh = SessionState.hasItem("traceAsh")
            local duration = TrackingSystem.getInvestigateTime(clue.type, hasTraceAsh)
            self.investigateTarget = clue
            self.investigateTimer = 0
            self.investigateDuration = duration
            self.investigateHasTraceAsh = hasTraceAsh
            self:addToast("正在调查...")
        end
        -- 调查推进在 update 中处理，此处不做完成动作

    elseif self.interactType == "collect" then
        local res = self.interactTarget
        res.collected = true
        local amount = res.amount
        -- 贪渊流派：高危区资源产出加成
        local tileX = math.floor(self.playerX)
        local tileY = math.floor(self.playerY)
        local curTile = self.map:getTile(tileX, tileY)
        if curTile and curTile.type == "danger" then
            local gEffect = getSchoolEffect()
            if gEffect and gEffect.dangerResMul then
                amount = math.floor(amount * gEffect.dangerResMul)
            end
        end
        -- 不死草：立即使用，全满HP + 清除所有debuff
        if res.type == "busicao" then
            CombatSystem.heal(CombatSystem.MAX_HP)
            CombatSystem.clearAllDebuffs()
            self:addToast("不死草生效！灵气全满，所有异状清除！")
            TutorialSystem.checkTrigger("collect")
            return
        end
        -- 区分会话资源和跨局资源
        if res.type == "lingshi" or res.type == "shouhun" or res.type == "tianjing" then
            SessionState.addResource(res.type, amount)
        else
            SessionState.addItem(res.type, amount)
        end
        self:addToast("获得 " .. (RES_NAMES[res.type] or res.type) .. " ×" .. amount)
        TutorialSystem.checkTrigger("collect")

    elseif self.interactType == "evacuate" then
        if not EvacuationSystem.evacuating then
            local eEffect = getSchoolEffect()
            EvacuationSystem.startEvacuation(self.interactTarget, {
                isCollapse = Timer.phase == "collapse",
                hasRushWard = self.rushWardTimer and self.rushWardTimer > 0,
                schoolTimeSave = eEffect and eEffect.evacTimeSave or 0,
                -- TODO Phase 2: 封印被动撤离效果
            })
            TutorialSystem.checkTrigger("evacuate")
        end
    end
end

function ExploreScreen:completeInvestigation()
    local clue = self.investigateTarget
    if not clue then return end

    local hasTraceAsh = self.investigateHasTraceAsh
    if hasTraceAsh then
        SessionState.addItem("traceAsh", -1)
    end
    TrackingSystem.investigate(clue, false)
    SessionState.stats.cluesInvestigated = SessionState.stats.cluesInvestigated + 1

    -- 根据线索类型生成信息提示
    local infoMsg = self:getClueInfoText(clue)
    self:addToast(infoMsg or "发现线索！")
    TutorialSystem.checkTrigger("investigate")

    -- 高危区线索每日任务
    local py = math.floor(self.playerY)
    if py / Config.MAP_HEIGHT > 0.7 then
        EventBus.emit("danger_clue_investigated")
    end

    self.investigateTarget = nil
    self.investigateTimer = 0
    self.investigateHasTraceAsh = nil
end

--- 根据线索类型返回调查后的信息文本
function ExploreScreen:getClueInfoText(clue)
    if clue.type == "footprint" then
        -- 足迹：显示附近异兽的大致方向
        local nearestBeast = self:findNearestActiveBeast()
        if nearestBeast then
            local dx = nearestBeast.x - clue.x
            local dy = nearestBeast.y - clue.y
            local dir = ""
            if math.abs(dy) > math.abs(dx) then
                dir = dy > 0 and "北方" or "南方"
            else
                dir = dx > 0 and "东方" or "西方"
            end
            return "足迹痕迹指向" .. dir
        end
        return "发现足迹，但踪迹已散"
    elseif clue.type == "resonance" then
        -- 共鸣：显示可能的异兽品质
        local ssrThreshold = 5 - (TrackingSystem.ssrReduceBonus or 0)
        if TrackingSystem.clueCount >= ssrThreshold then
            return "共鸣强烈！感应到SSR级灵气"
        elseif TrackingSystem.clueCount >= 3 then
            return "共鸣明显，感应到SR级灵气"
        else
            return "共鸣微弱，周围有R级异兽活动"
        end
    elseif clue.type == "nest" then
        -- 巢穴：显示异兽种类
        local biome = SessionState.selectedBiome
        local beastInfo = biome
            and BeastData.getRandomForBiome(biome)
            or BeastData.getRandom()
        if beastInfo then
            return "巢穴痕迹：疑似" .. beastInfo.name .. "栖息地"
        end
        return "发现异兽巢穴"
    elseif clue.type == "scentMark" then
        -- 气息印记：揭示附近2格资源
        local revealed = 0
        for _, res in ipairs(self.map.resources) do
            if not res.collected then
                local rdx = res.x - clue.x
                local rdy = res.y - clue.y
                if rdx * rdx + rdy * rdy <= 4 then
                    res.scentRevealed = true
                    revealed = revealed + 1
                end
            end
        end
        if revealed > 0 then
            return "气息印记揭示了附近" .. revealed .. "处资源"
        end
        return "气息印记已消散，附近无资源"
    end
    return "发现线索！"
end

function ExploreScreen:findNearestActiveBeast()
    local best, bestDist = nil, math.huge
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            local dx = beast.x - self.playerX
            local dy = beast.y - self.playerY
            local d = dx * dx + dy * dy
            if d < bestDist then best = beast; bestDist = d end
        end
    end
    return best
end

function ExploreScreen:onSuppressResult(result)
    if not self.activeBeast then return end
    if result == "success" then
        local beast = self.activeBeast
        local available = CaptureSystem.getAvailableSealers(SessionState.inventory)
        if #available > 0 then
            -- 显示封灵器选择弹窗
            self.sealerSelectBeast = beast
            self.sealerSelectList = available
            self.sealerSelectActive = true
            self.paused = true
        else
            self:addToast("没有封灵器！")
            beast.aiState = "flee"
            self.activeBeast = nil
        end
    else
        -- 压制失败：检查流派重试（压制大成）
        local retryEffect = getSchoolEffect()
        if retryEffect and retryEffect.qteRetry and retryEffect.qteRetry > 0
           and not self.schoolRetryUsed then
            self.schoolRetryUsed = true
            self:addToast("流派之力！再次压制")
            self.pendingSuppressRetry = true
        elseif SessionState.hasItem("sealEcho") and not SessionState.sealEchoUsed then
            SessionState.sealEchoUsed = true
            self:addToast("封印回响！可再次压制")
            self.pendingSuppressRetry = true
        else
            self:addToast("压制失败！")
            -- 猰貐假死：HP归零后重生
            if self.activeBeast.revivable and BeastAI.triggerFakeDeath(self.activeBeast) then
                self:addToast("猰貐进入假死状态！")
            else
                self.activeBeast.aiState = "flee"
            end
            self.activeBeast = nil
        end
    end
end

--- 封灵器选择回调
function ExploreScreen:onSealerSelected(sealerInfo)
    self.sealerSelectActive = false
    self.paused = false
    local beast = self.sealerSelectBeast
    if not beast or not sealerInfo then
        if beast then beast.aiState = "flee" end
        self.activeBeast = nil
        return
    end

    local contract = CaptureSystem.attemptCapture(
        beast, sealerInfo.tier, SessionState.inventory, sealerInfo.key)
    if contract then
        beast.aiState = "captured"
        local CaptureOverlay = require("screens.CaptureOverlay")
        ScreenManager.push(CaptureOverlay, {
            beast = beast,
            contract = contract,
        })
    end
    self.activeBeast = nil
end

function ExploreScreen:onEvacuationComplete()
    local contracts = SessionState.getContracts()
    if #contracts == 0 then
        self:goToResult({})
        return
    end
    local soulCharmCount = SessionState.getItemCount("soulCharm")
    -- TODO Phase 2: 封印被动灵契稳定效果
    local hasIceSilk = false
    local evacEffect = getSchoolEffect()
    local schoolProtect = evacEffect and evacEffect.contractProtect or 0
    -- 撤离大成：安全逃脱（无灵契损失）
    if evacEffect and evacEffect.safeEscape then
        self:goToResult({})
        return
    end
    local unstable = EvacuationSystem.checkContractStability(contracts, soulCharmCount, hasIceSilk, schoolProtect)
    if soulCharmCount > 0 and #unstable > 0 then
        SessionState.addItem("soulCharm", -1)
    end
    if #unstable > 0 then
        -- 推入 ContractQTEOverlay
        local ContractQTEOverlay = require("screens.ContractQTEOverlay")
        EvacuationSystem.startContractQTE(unstable)
        ScreenManager.push(ContractQTEOverlay, { contracts = unstable })
    else
        self:goToResult({})
    end
end

function ExploreScreen:onEvacuationResult(success, lostContracts)
    TutorialSystem.checkTrigger("evacuation_done")
    self:goToResult(lostContracts)
end

function ExploreScreen:goToResult(lostContracts, evacType)
    -- 持久化当前 HP 到存档
    GameState.data.hp = math.max(1, CombatSystem.hp)
    GameState.save()

    -- 从 contracts 中移除丢失的
    local remaining = {}
    for _, c in ipairs(SessionState.getContracts()) do
        local lost = false
        for _, lc in ipairs(lostContracts) do
            if lc == c then lost = true; break end
        end
        if not lost then table.insert(remaining, c) end
    end
    local ResultScreen = require("screens.ResultScreen")
    ScreenManager.switch(ResultScreen, {
        contracts = remaining,
        lostContracts = lostContracts,
        resources = SessionState.resources,
        stats = SessionState.stats,
        elapsed = Timer.elapsed,
        evacType = evacType or "normal",
    })
end

function ExploreScreen:onSpiritCollapseEnd()
    -- 灵气溃散结束：强制逃脱
    local contracts = SessionState.getContracts()
    local lostContracts = {}

    -- 按 SSR→SR→R 顺序丢失1只
    local priorities = { SSR = 1, SR = 2, R = 3 }
    local sorted = {}
    for _, c in ipairs(contracts) do table.insert(sorted, c) end
    table.sort(sorted, function(a, b)
        return (priorities[a.quality] or 9) < (priorities[b.quality] or 9)
    end)
    if #sorted > 0 then
        table.insert(lostContracts, sorted[1])
    end

    -- 灵石损失40%，兽魂/天晶清零
    SessionState.resources.lingshi = math.floor((SessionState.resources.lingshi or 0) * 0.6)
    SessionState.resources.shouhun = 0
    SessionState.resources.tianjing = 0

    -- 溃散（死亡）恢复 1 滴血量
    CombatSystem.hp = 1

    self:goToResult(lostContracts, "collapse")
end

function ExploreScreen:forceEnd()
    local overtime = Timer.getOvertimeSeconds()
    local contracts = SessionState.getContracts()
    local lostContracts = {}

    if overtime > 60 then
        -- 超时>60秒：全部灵契丢失，灵石保留20%
        for _, c in ipairs(contracts) do
            table.insert(lostContracts, c)
        end
        SessionState.resources.lingshi = math.floor((SessionState.resources.lingshi or 0) * 0.2)
        SessionState.resources.shouhun = 0
        SessionState.resources.tianjing = 0
    elseif overtime > 30 then
        -- 超时30-60秒：SSR/SR灵契丢失，R保留50%，灵石保留40%
        for _, c in ipairs(contracts) do
            if c.quality == "SSR" or c.quality == "SR" then
                table.insert(lostContracts, c)
            elseif math.random() > 0.5 then
                table.insert(lostContracts, c)
            end
        end
        SessionState.resources.lingshi = math.floor((SessionState.resources.lingshi or 0) * 0.4)
        SessionState.resources.shouhun = 0
        SessionState.resources.tianjing = 0
    else
        -- 超时<30秒：仅SSR灵契丢失，灵石保留60%
        for _, c in ipairs(contracts) do
            if c.quality == "SSR" then
                table.insert(lostContracts, c)
            end
        end
        SessionState.resources.lingshi = math.floor((SessionState.resources.lingshi or 0) * 0.6)
    end

    self:goToResult(lostContracts, "forced")
end

--- 检查本局是否已捕获某种异兽（用于被动效果判定）
function ExploreScreen:hasCapturedBeast(beastId)
    for _, c in ipairs(SessionState.getContracts()) do
        if c.beastId == beastId then return true end
    end
    return false
end

--- 紧急逃脱（collapse阶段，距撤离点>8格）
function ExploreScreen:doEmergencyEscape()
    if not self.emergencyEscapeAvailable then return end
    local contracts = SessionState.getContracts()
    -- 撤离流大成：紧急逃脱无灵契损失
    local evacEffect = getSchoolEffect()
    if evacEffect and evacEffect.safeEscape then
        self:addToast("紧急逃脱！流派之力保全灵契")
        self:goToResult({}, "normal")
        return
    end
    local lostContracts = EvacuationSystem.emergencyEscape(contracts)
    if #lostContracts > 0 then
        self:addToast("紧急逃脱！丢失了" .. lostContracts[1].name)
    elseif #contracts == 0 then
        SessionState.resources.lingshi = math.floor((SessionState.resources.lingshi or 0) * 0.5)
        self:addToast("紧急逃脱！灵石损失50%")
    end
    self:goToResult(lostContracts, "normal")
end

--- 使用特殊道具
function ExploreScreen:useSpecialItem(itemId)
    if itemId == "rushWard" then
        if SessionState.hasItem("rushWard") and not (self.rushWardTimer and self.rushWardTimer > 0) then
            SessionState.addItem("rushWard", -1)
            self.rushWardTimer = 60
            self.rushWardActive = true
            self:addToast("疾风符生效！移速+30%，持续60秒")
        end
    elseif itemId == "beastEye" then
        if SessionState.hasItem("beastEye") and not (self.beastEyeTimer and self.beastEyeTimer > 0) then
            SessionState.addItem("beastEye", -1)
            -- 追迹流大成：延长至30秒
            local effect = getSchoolEffect()
            local duration = (effect and effect.beastEyeDuration) or 15
            self.beastEyeTimer = duration
            self:addToast("兽目珠开眼！显示异兽位置" .. duration .. "秒")
        end
    elseif itemId == "lingquanWan" or itemId == "jianzhulu" then
        self:useRecoveryItem(itemId)
    end
end

--- 使用恢复道具（灵泉丸/绛珠露）
function ExploreScreen:useRecoveryItem(itemId)
    if not SessionState.hasItem(itemId) then return end
    if CombatSystem.collapsed then
        self:addToast("溃散状态无法使用恢复道具")
        return
    end
    if CombatSystem.hp >= CombatSystem.MAX_HP then
        self:addToast("灵气已满，无需使用")
        return
    end
    -- 使用中不可重复触发
    if self.recoveryUsing then
        self:addToast("正在使用道具...")
        return
    end
    -- 检查是否有异兽在chase/attack状态且距离较近（距离<4格不可使用）
    local canUse = true
    -- 撤离流精通+：chase下也可使用
    local effectEvac = getSchoolEffect()
    local allowInChase = effectEvac and effectEvac.recoveryCastMul
    for _, beast in ipairs(self.beasts or {}) do
        if beast.aiState == "attack" then
            local dist = math.sqrt((beast.x - self.playerX)^2 + (beast.y - self.playerY)^2)
            if dist < 4 then
                canUse = false
                break
            end
        elseif beast.aiState == "chase" and not allowInChase then
            local dist = math.sqrt((beast.x - self.playerX)^2 + (beast.y - self.playerY)^2)
            if dist < 4 then
                canUse = false
                break
            end
        end
    end
    if not canUse then
        self:addToast("附近有异兽追击，无法使用！")
        return
    end

    -- 开始使用：消耗道具，设置吟唱计时
    SessionState.addItem(itemId, -1)
    local healAmount, castTime
    if itemId == "lingquanWan" then
        healAmount = 2
        castTime = 1.0
    else -- jianzhulu
        healAmount = 5
        castTime = 0.5
    end
    -- 撤离流精通+：耗时减半
    if effectEvac and effectEvac.recoveryCastMul then
        castTime = castTime * effectEvac.recoveryCastMul
    end
    self.recoveryUsing = {
        itemId = itemId,
        healAmount = healAmount,
        timer = castTime,
        maxTime = castTime,
    }
    local name = (itemId == "lingquanWan") and "灵泉丸" or "绛珠露"
    self:addToast("使用" .. name .. "中...")
end

function ExploreScreen:addToast(msg)
    table.insert(self.toasts, { text = msg, life = 2.5, maxLife = 2.5 })
end

------------------------------------------------------------
-- 输入
------------------------------------------------------------

function ExploreScreen:onInput(action, sx, sy)
    -- 灵境传说卡片：点击关闭
    if self.realmLegend and not self.realmLegendDismissed and self.realmLegendAlpha > 0.5 then
        if action == "down" then
            self.realmLegendDismissed = true
        end
        return true -- 卡片显示期间拦截所有输入
    end

    -- 封灵器选择弹窗拦截所有输入
    if self.sealerSelectActive then
        if action == "down" then
            for _, btn in ipairs(self.sealerSelectButtons or {}) do
                if sx >= btn.x and sx <= btn.x + btn.w
                   and sy >= btn.y and sy <= btn.y + btn.h then
                    self:onSealerSelected(btn.info)
                    return true
                end
            end
        end
        return true
    end

    -- 小地图展开状态：任意点击关闭
    if self.minimapExpanded then
        if action == "down" then
            self.minimapExpanded = false
        end
        return true
    end

    if self.paused then return false end

    if action == "down" then
        -- 小地图点击展开
        if self.minimapBounds then
            local mb = self.minimapBounds
            if sx >= mb.x and sx <= mb.x + mb.w and sy >= mb.y and sy <= mb.y + mb.h then
                self.minimapExpanded = true
                return true
            end
        end

        -- 紧急逃脱按钮
        if self.emergencyEscapeBtn then
            local eb = self.emergencyEscapeBtn
            if sx >= eb.x and sx <= eb.x + eb.w
               and sy >= eb.y and sy <= eb.y + eb.h then
                self:doEmergencyEscape()
                return true
            end
        end

        -- 技能按钮
        if self.skillBtn then
            local sb = self.skillBtn
            local dx = sx - sb.x
            local dy = sy - sb.y
            if (dx * dx + dy * dy) < (sb.r * sb.r) then
                local tx = math.floor(self.playerX)
                local ty = math.floor(self.playerY)
                local tile = self.map:getTile(tx, ty)
                local inDanger = tile and tile.type == "danger" or false
                SkillSystem.useSkill(self.playerX, self.playerY, self.playerFacing, self.beasts, inDanger)
                return true
            end
        end

        -- 特殊道具按钮
        if self.itemButtons then
            for _, btn in ipairs(self.itemButtons) do
                if sx >= btn.x and sx <= btn.x + btn.w
                   and sy >= btn.y and sy <= btn.y + btn.h then
                    self:useSpecialItem(btn.id)
                    return true
                end
            end
        end

        if self:isInInteractButton(sx, sy) then
            self:doInteract()
            return true
        end
        -- 摇杆激活
        if VirtualJoystick.onTouchDown(sx, sy, Camera.logW, Camera.logH) then
            return true
        end
        return false

    elseif action == "move" then
        VirtualJoystick.onTouchMove(sx, sy)
        return true

    elseif action == "up" then
        VirtualJoystick.onTouchUp()
        return true
    end
    return false
end

function ExploreScreen:isInInteractButton(sx, sy)
    if not self.interactType then return false end
    local logW, logH = Camera.logW, Camera.logH
    local btnX = logW * 0.78
    local btnY = logH * 0.88
    local btnR = 32
    local dx = sx - btnX
    local dy = sy - btnY
    return (dx * dx + dy * dy) < (btnR * btnR)
end

------------------------------------------------------------
-- 渲染（已拆分至 screens/ExploreRender.lua）
------------------------------------------------------------
-- 注入渲染方法
require("screens.ExploreRender")(ExploreScreen)

return ExploreScreen
