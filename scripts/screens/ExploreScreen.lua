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
        if beast and not beast.ccImmune then
            beast.stunTimer = data.duration
            beast.prevAiState = beast.aiState
            beast.aiState = "stunned"
        end
    end, self)
    EventBus.on("beast_slowed", function(data)
        local beast = data.beast
        if beast and not beast.skillImmune then
            beast.slowTimer = data.duration
            beast.slowMul = data.speedMul
        end
    end, self)
    EventBus.on("beast_frozen", function(data)
        local beast = data.beast
        if beast and not beast.ccImmune then
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
           and beast.aiState ~= "burst" and not beast.fakeDeath then
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
        elseif SessionState.hasItem("sealEcho") and not SessionState.sealEchoUsed then
            -- 检查封印回响
            SessionState.sealEchoUsed = true
            self:addToast("封印回响！可再次压制")
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
-- 渲染
------------------------------------------------------------

function ExploreScreen:render(vg, logW, logH, t)
    Camera.resize(logW, logH)
    local P = InkPalette
    local ppu = Camera.ppu

    -- 震屏偏移
    local shakeOX, shakeOY = 0, 0
    if self.shakeTimer > 0 then
        shakeOX = math.sin(t * 40) * self.shakeIntensity
        shakeOY = math.cos(t * 50) * self.shakeIntensity * 0.7
    end

    nvgSave(vg)
    nvgTranslate(vg, shakeOX, shakeOY)

    -- Layer 1: 宣纸底
    InkRenderer.drawPaperBase(vg, logW, logH, t)

    -- Layer 1.5: 瓦片
    self:renderTiles(vg, logW, logH, t)

    -- Layer 2: 实体
    self:renderEntities(vg, logW, logH, t)

    -- Layer 3: 迷雾
    local psx, psy = Camera.toScreen(self.playerX, self.playerY)
    local visionPx = Config.VISION_RADIUS * ppu
    InkRenderer.drawFog(vg, logW, logH, psx, psy, visionPx, t, Timer.getCollapseProgress())

    -- Layer 4: HUD + 特效
    if Config.ATMOSPHERE then
        InkRenderer.drawAtmosphere(vg, logW, logH, t)
    end
    InkRenderer.drawEdgeWhitespace(vg, logW, logH)

    self:renderHUD(vg, logW, logH, t)
    self:renderBottomBar(vg, logW, logH, t)
    self:renderControls(vg, logW, logH, t)
    self:renderMinimap(vg, logW, logH, t)
    self:renderToasts(vg, logW, logH, t)

    -- 受击闪红叠层
    if CombatSystem.hitFlashTimer > 0 then
        local flashAlpha = math.min(0.35, CombatSystem.hitFlashTimer / 0.3 * 0.35)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0.8, 0.1, 0.05, flashAlpha))
        nvgFill(vg)
    end

    -- 瘴气墨染叠层
    if CombatSystem.miasmaDmgFlash > 0 then
        local inkAlpha = math.min(0.25, CombatSystem.miasmaDmgFlash / 1.0 * 0.25)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0.05, 0.03, 0.08, inkAlpha))
        nvgFill(vg)
    end

    -- 溃散倒计时（屏幕中央大字）
    if CombatSystem.collapsed then
        local remain = math.ceil(CombatSystem.collapseTimer)
        local pulse = 0.7 + math.sin(t * 5) * 0.3
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(0.8, 0.15, 0.1, pulse))
        nvgText(vg, logW * 0.5, logH * 0.3, "灵气溃散")
        nvgFontSize(vg, 28)
        nvgText(vg, logW * 0.5, logH * 0.3 + 45, remain .. " 秒")
    end

    -- 封灵器选择弹窗
    if self.sealerSelectActive then
        self:renderSealerSelect(vg, logW, logH, t)
    end

    -- 灵境传说卡片叠层
    if self.realmLegend and self.realmLegendAlpha > 0.01 then
        self:renderRealmLegend(vg, logW, logH, t)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- Layer 1.5: 瓦片渲染
------------------------------------------------------------

function ExploreScreen:renderTiles(vg, logW, logH, t)
    local bounds = Camera.getViewBounds()
    local ppu = Camera.ppu

    -- Pass 1: 色块层 — 大半径底色晕染，相邻瓦片互相渗透
    for gy = bounds.minY, bounds.maxY do
        for gx = bounds.minX, bounds.maxX do
            local tile = self.map:getTile(gx, gy)
            if tile then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    local jx, jy = InkTileRenderer.jitter(gx, gy, ppu)
                    InkTileRenderer.drawBase(vg, tile, sx + jx, sy + jy, ppu, t, fogState)
                end
            end
        end
    end

    -- Pass 2: 细节层 — 笔触/纹理（允许越界到邻格）
    for gy = bounds.minY, bounds.maxY do
        for gx = bounds.minX, bounds.maxX do
            local tile = self.map:getTile(gx, gy)
            if tile then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    local jx, jy = InkTileRenderer.jitter(gx, gy, ppu)
                    InkTileRenderer.drawDetail(vg, tile, sx + jx, sy + jy, ppu, t, fogState)
                end
            end
        end
    end
end

------------------------------------------------------------
-- Layer 2: 实体渲染
------------------------------------------------------------

function ExploreScreen:renderEntities(vg, logW, logH, t)
    local ppu = Camera.ppu

    -- 行迹墨尘
    for _, trail in ipairs(self.playerTrails) do
        if Camera.inView(trail.x, trail.y) then
            local sx, sy = Camera.toScreen(trail.x, trail.y)
            local a = trail.alpha * (trail.life / trail.maxLife)
            BrushStrokes.inkDotStable(vg, sx, sy, 2, InkPalette.inkLight, a, 0)
        end
    end

    -- 线索
    for _, clue in ipairs(self.map.clues) do
        if not clue.investigated and FogOfWar.isEntityVisible(clue.x, clue.y) then
            if Camera.inView(clue.x, clue.y) then
                local sx, sy = Camera.toScreen(clue.x, clue.y)
                InkRenderer.drawClue(vg, clue, sx, sy, ppu, t)
            end
        end
    end

    -- 资源（TODO Phase 2: 封印被动资源透视）
    local resSeeThroughFog = false
    for _, res in ipairs(self.map.resources) do
        if not res.collected and (FogOfWar.isEntityVisible(res.x, res.y) or resSeeThroughFog) then
            if Camera.inView(res.x, res.y) then
                local sx, sy = Camera.toScreen(res.x, res.y)
                local playerDist = math.sqrt(
                    (res.x - self.playerX) ^ 2 + (res.y - self.playerY) ^ 2
                )
                InkRenderer.drawResource(vg, res, sx, sy, ppu, t, playerDist)
            end
        end
    end

    -- 撤离点
    for _, ep in ipairs(self.map.evacuationPoints) do
        if Camera.inView(ep.x, ep.y) then
            local sx, sy = Camera.toScreen(ep.x, ep.y)
            local progress = 0
            if EvacuationSystem.evacuating and EvacuationSystem.currentPoint == ep then
                progress = EvacuationSystem.getProgress()
            end
            InkRenderer.drawEvacPoint(vg, sx, sy, ppu, t, progress)
        end
    end

    -- 地面墨迹/毒迹区域
    for _, patch in ipairs(self.inkPatches) do
        if Camera.inView(patch.x, patch.y) then
            local sx, sy = Camera.toScreen(patch.x, patch.y)
            local alpha = math.min(0.5, patch.life / patch.maxLife * 0.5)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, ppu * 1.2)
            nvgFillColor(vg, nvgRGBAf(0.05, 0.03, 0.08, alpha))
            nvgFill(vg)
        end
    end

    -- 异兽
    local beastEyeActive = self.beastEyeTimer and self.beastEyeTimer > 0
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            local normalVisible = FogOfWar.isEntityVisible(beast.x, beast.y) and Camera.inView(beast.x, beast.y)
            local eyeRevealed = beastEyeActive and Camera.inView(beast.x, beast.y)
            if normalVisible or eyeRevealed then
                local sx, sy = Camera.toScreen(beast.x, beast.y)
                -- 兽目珠揭示：金色灵光标记（视野外异兽画光环，隐形异兽也显形）
                if eyeRevealed then
                    local baseR = ppu * beast.bodySize * 1.8
                    local pulseR = baseR + math.sin(t * 4) * ppu * 0.15
                    -- 外圈金色光晕（填充）
                    local glowPaint = nvgRadialGradient(vg, sx, sy, pulseR * 0.3, pulseR,
                        nvgRGBAf(0.90, 0.75, 0.15, 0.35 + math.sin(t * 3) * 0.1),
                        nvgRGBAf(0.85, 0.65, 0.10, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, pulseR)
                    nvgFillPaint(vg, glowPaint)
                    nvgFill(vg)
                    -- 内圈描边
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, baseR * 0.6)
                    nvgStrokeColor(vg, nvgRGBAf(0.95, 0.80, 0.20, 0.6 + math.sin(t * 5) * 0.15))
                    nvgStrokeWidth(vg, 2.0)
                    nvgStroke(vg)
                end
                if beast.invisible and not eyeRevealed then
                    -- 隐形异兽：仅显示草叶扰动粒子
                    for pi = 1, 3 do
                        local px = sx + math.sin(t * 2 + pi * 2.1) * ppu * 0.4
                        local py = sy + math.cos(t * 1.5 + pi * 1.7) * ppu * 0.3
                        local pa = 0.15 + math.sin(t * 3 + pi) * 0.08
                        nvgBeginPath(vg)
                        nvgCircle(vg, px, py, 2)
                        nvgFillColor(vg, nvgRGBAf(0.3, 0.5, 0.2, pa))
                        nvgFill(vg)
                    end
                elseif beast.fakeDeath then
                    -- 猰貐假死：淡化显示
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, 0.3)
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                    nvgRestore(vg)
                else
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                end
            end
        end
    end

    -- 玩家（始终绘制在最上层）
    local psx, psy = Camera.toScreen(self.playerX, self.playerY)
    -- 血量≤3：轻微抖动虚弱特效（仅视觉，不影响实际坐标）
    if CombatSystem.hp <= 3 and CombatSystem.hp > 0 then
        local shakeAmt = (4 - CombatSystem.hp) * 0.4  -- hp3→0.4, hp2→0.8, hp1→1.2
        psx = psx + math.sin(t * 17.3) * shakeAmt
        psy = psy + math.cos(t * 13.7) * shakeAmt * 0.6
    end
    InkRenderer.drawPlayer(vg, psx, psy, ppu, self.playerFacing, t)

    -- Debuff指示（玩家脚下颜色环 + 计时文字）
    local P = InkPalette
    local activeDebuffs = CombatSystem.debuffs
    if activeDebuffs then
        local debuffIdx = 0
        -- debuff 颜色映射
        local debuffColors = {
            petrify = P.inkMedium,
            sticky  = P.jade,
            burn    = P.cinnabar,
            dizzy   = P.gold,
            ink     = P.inkDark,
        }
        for debuffId, debuff in pairs(activeDebuffs) do
            if debuff.timer and debuff.timer > 0 then
                debuffIdx = debuffIdx + 1
                local ringR = ppu * 0.5 + debuffIdx * 4
                local dColor = debuffColors[debuffId] or P.inkMedium
                local remain = debuff.timer
                local pulse = 0.4 + math.sin(t * 3 + debuffIdx * 1.5) * 0.15

                -- 颜色环
                nvgBeginPath(vg)
                nvgCircle(vg, psx, psy, ringR)
                nvgStrokeWidth(vg, 2.0)
                nvgStrokeColor(vg, nvgRGBAf(dColor.r, dColor.g, dColor.b, pulse))
                nvgStroke(vg)

                -- 计时文字（环外侧小字）
                local def = CombatSystem.DEBUFF_DEFS[debuffId]
                local label = (def and def.name or debuffId) .. string.format("%.0f", remain)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBAf(dColor.r, dColor.g, dColor.b, pulse + 0.15))
                nvgText(vg, psx, psy + ringR + 2, label)
            end
        end
    end

    -- 恢复道具施法进度（玩家头顶）
    if self.recoveryUsing then
        local castProg = 1.0 - (self.recoveryUsing.timer / (self.recoveryUsing.maxTime or 2.0))
        castProg = math.max(0, math.min(1, castProg))
        -- 圆弧进度
        nvgBeginPath(vg)
        nvgArc(vg, psx, psy - ppu * 0.8, 12,
            -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * castProg, NVG_CW)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.75))
        nvgStroke(vg)
    end

    -- 疾风符生效视觉反馈：风纹短弧
    if self.rushWardTimer and self.rushWardTimer > 0 then
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        local windAlpha = math.min(0.5, self.rushWardTimer / 10) -- 快结束时淡出
        for wi = 1, 3 do
            local angle = t * 3.0 + wi * 2.09
            local wr = ppu * 0.7 + math.sin(t * 2 + wi) * ppu * 0.15
            nvgBeginPath(vg)
            nvgArc(vg, psx, psy, wr, angle, angle + 0.8, NVG_CW)
            nvgStrokeWidth(vg, 1.2)
            nvgStrokeColor(vg, nvgRGBAf(InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b, windAlpha * (0.3 + wi * 0.1)))
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    -- 撤离路径指引：warning/danger/collapse 阶段显示指向最近撤离点的箭头
    local curPhase = Timer.getPhase()
    if curPhase == "warning" or curPhase == "danger" or curPhase == "collapse" then
        local nearPt, nearDist = EvacuationSystem.getNearestPoint(self.playerX, self.playerY)
        if nearPt and nearDist > 2.0 then
            local dx = nearPt.x - self.playerX
            local dy = nearPt.y - self.playerY
            local angle = math.atan2(dy, dx)
            local arrowDist = ppu * 2.0
            local ax = psx + math.cos(angle) * arrowDist
            local ay = psy + math.sin(angle) * arrowDist

            -- 闪烁透明度（warning较温和，danger/collapse更急迫）
            local urgency = (curPhase == "warning") and 0.5 or 0.8
            local pulse = urgency * (0.5 + math.sin(t * 3) * 0.3)

            -- 虚线 + 箭头
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)

            -- 虚线段（从玩家附近到箭头位置）
            local segments = 4
            for si = 1, segments do
                local frac0 = (si - 1) / segments * 0.8 + 0.2
                local frac1 = frac0 + 0.12
                local x0 = psx + math.cos(angle) * arrowDist * frac0
                local y0 = psy + math.sin(angle) * arrowDist * frac0
                local x1 = psx + math.cos(angle) * arrowDist * frac1
                local y1 = psy + math.sin(angle) * arrowDist * frac1
                nvgBeginPath(vg)
                nvgMoveTo(vg, x0, y0)
                nvgLineTo(vg, x1, y1)
                nvgStrokeWidth(vg, 1.5)
                nvgStrokeColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, pulse))
                nvgStroke(vg)
            end

            -- 箭头三角
            local aSize = 5
            local a1x = ax + math.cos(angle) * aSize
            local a1y = ay + math.sin(angle) * aSize
            local a2x = ax + math.cos(angle + 2.5) * aSize
            local a2y = ay + math.sin(angle + 2.5) * aSize
            local a3x = ax + math.cos(angle - 2.5) * aSize
            local a3y = ay + math.sin(angle - 2.5) * aSize
            nvgBeginPath(vg)
            nvgMoveTo(vg, a1x, a1y)
            nvgLineTo(vg, a2x, a2y)
            nvgLineTo(vg, a3x, a3y)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, pulse))
            nvgFill(vg)

            nvgRestore(vg)
        end
    end
end

------------------------------------------------------------
-- Layer 4: HUD
------------------------------------------------------------

function ExploreScreen:renderHUD(vg, logW, logH, t)
    local P = InkPalette

    -- 顶部倒计时
    local timeStr = Timer.formatRemaining()
    local phase = Timer.getPhase()
    local phaseName = Timer.getPhaseName()

    -- 倒计时颜色
    local timeColor = P.inkStrong
    local timeAlpha = 1.0
    if phase == "warning" then
        timeColor = P.gold
    elseif phase == "danger" or phase == "collapse" or phase == "collapsed" then
        timeColor = P.cinnabar
        timeAlpha = math.sin(t * 4) * 0.2 + 0.75
    end

    -- 倒计时文字
    local timeY = logH * 0.04
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(timeColor.r, timeColor.g, timeColor.b, timeAlpha))
    nvgText(vg, logW * 0.5, timeY, timeStr)

    -- 阶段名
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
    nvgText(vg, logW * 0.5, timeY + 40, phaseName)

    -- HP血条（左上角10滴水墨滴）
    self:renderHPBar(vg, logW, logH, t)

    -- 品质印章
    if self.qualityStamp and self.qualityStampAlpha > 0.01 then
        local stampColor = self.qualityStamp == "SSR" and P.gold or P.azure
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(stampColor.r, stampColor.g, stampColor.b, self.qualityStampAlpha))
        nvgText(vg, 12, timeY + 4, self.qualityStamp)
    end
end

------------------------------------------------------------
-- 底部信息条
------------------------------------------------------------

function ExploreScreen:renderBottomBar(vg, logW, logH, t)
    local P = InkPalette
    local barY = logH * 0.74
    local barH = logH * 0.09
    local barX = logW * 0.05
    local barW = logW * 0.90

    -- 背景（宣纸底 + 飞白边框）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.78))
    nvgFill(vg)
    -- 飞白笔触边框（取代标准描边）
    BrushStrokes.inkRect(vg, barX, barY, barW, barH, P.inkLight, 0.30, 51)

    -- 第一行：线索进度 + 灵契
    local row1Y = barY + barH * 0.30
    local dotStartX = barX + 16

    -- 线索圆点 (5个) → 14px 不规则墨点 + ±5% 大小抖动
    for i = 1, 5 do
        local dotSeed = i * 37 + 11
        local sizeJitter = 1.0 + ((dotSeed % 10) - 5) * 0.01  -- ±5%
        local cx = dotStartX + (i - 1) * 20
        local dotR = 7 * sizeJitter  -- 14px 直径
        if i <= TrackingSystem.clueCount then
            -- 已收集：朱砂不规则实心墨点
            BrushStrokes.inkDotStable(vg, cx, row1Y, dotR, P.cinnabar, 0.85, dotSeed)
        else
            -- 未收集：淡墨空心描边（3段飞白短弧）
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            for seg = 1, 3 do
                local startA = (seg - 1) * math.pi * 2 / 3 + ((dotSeed * seg) % 30) * 0.02
                nvgBeginPath(vg)
                nvgArc(vg, cx, row1Y, dotR * 0.85, startA, startA + math.pi * 0.55, NVG_CW)
                nvgStrokeWidth(vg, 1.0 + (seg % 2) * 0.4)
                nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40))
                nvgStroke(vg)
            end
            nvgRestore(vg)
        end
    end

    -- 封灵器库存（线索点右侧）
    local sealerTypes = {
        { key = "sealer_free", label = "素", color = P.inkMedium },
        { key = "sealer_t2",   label = "玉", color = P.jade },
        { key = "sealer_t3",   label = "金", color = P.gold },
        { key = "sealer_t4",   label = "命", color = P.azure },
        { key = "sealer_t5",   label = "沌", color = P.cinnabar },
    }
    local sealerX = dotStartX + 5 * 20 + 14
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for _, st in ipairs(sealerTypes) do
        local cnt = SessionState.getItemCount(st.key)
        if cnt > 0 then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBAf(st.color.r, st.color.g, st.color.b, 0.65))
            nvgText(vg, sealerX, row1Y, st.label)
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.70))
            nvgText(vg, sealerX + 13, row1Y, tostring(cnt))
            sealerX = sealerX + 28
        end
    end

    -- 灵契印章（朱砂方印风格）
    local contractCount = SessionState.getContractCount()
    local cntLabel = ({ [0]="零",[1]="壹",[2]="贰",[3]="叁",[4]="肆",[5]="伍" })[contractCount] or tostring(contractCount)
    do
        local stampSize = 30
        local stampX = barX + barW - stampSize - 10
        local stampY = row1Y - stampSize * 0.5
        -- 方印底色
        nvgBeginPath(vg)
        nvgRoundedRect(vg, stampX, stampY, stampSize, stampSize, 3)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, contractCount > 0 and 0.18 or 0.08))
        nvgFill(vg)
        -- 飞白笔触边框
        BrushStrokes.inkRect(vg, stampX, stampY, stampSize, stampSize, P.cinnabar, contractCount > 0 and 0.60 or 0.25, 88)
        -- 竖排文字："灵契" + 数量
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local stampCX = stampX + stampSize * 0.5
        local stampCY = stampY + stampSize * 0.5
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, contractCount > 0 and 0.85 or 0.35))
        nvgText(vg, stampCX, stampCY - 6, "灵契")
        nvgFontSize(vg, 13)
        nvgText(vg, stampCX, stampCY + 7, cntLabel)
    end

    -- 第二行：本局道具（具象化墨绘图标 + 汉字标签 + 数量）
    local row2Y = barY + barH * 0.74
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local items = {
        { label = "灰", count = SessionState.getItemCount("traceAsh"), color = P.inkMedium, icon = "ash" },
        { label = "砂", count = SessionState.getItemCount("mirrorSand"), color = P.azure, icon = "sand" },
        { label = "符", count = SessionState.getItemCount("soulCharm"), color = P.gold, icon = "charm" },
    }
    local ix = barX + 14
    for idx, item in ipairs(items) do
        local icx = ix + 2
        local icy = row2Y
        local iconS = 8

        if item.icon == "ash" then
            -- 追迹灰：3条飘散短弧线（模拟灰烬飘动）
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            for li = 1, 3 do
                local yOff = (li - 2) * iconS * 0.35
                nvgBeginPath(vg)
                nvgMoveTo(vg, icx - iconS * 0.5, icy + yOff)
                nvgQuadTo(vg, icx, icy + yOff - iconS * 0.2, icx + iconS * 0.5, icy + yOff + iconS * 0.1)
                nvgStrokeWidth(vg, 1.0 + li * 0.3)
                nvgStrokeColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.65 - li * 0.1))
                nvgStroke(vg)
            end
            nvgRestore(vg)
        elseif item.icon == "sand" then
            -- 镇灵砂：散落的小菱形晶体（4颗）
            nvgSave(vg)
            for ci = 1, 4 do
                local hash = (ci * 31 + idx * 7) % 20
                local dx = (hash - 10) * iconS * 0.06
                local dy = ((ci - 2.5)) * iconS * 0.28
                local ds = iconS * 0.22
                nvgBeginPath(vg)
                nvgMoveTo(vg, icx + dx, icy + dy - ds)
                nvgLineTo(vg, icx + dx + ds * 0.7, icy + dy)
                nvgLineTo(vg, icx + dx, icy + dy + ds)
                nvgLineTo(vg, icx + dx - ds * 0.7, icy + dy)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.55))
                nvgFill(vg)
            end
            nvgRestore(vg)
        elseif item.icon == "charm" then
            -- 归魂符：长方形符纸 + 中心符文线
            nvgSave(vg)
            local cw = iconS * 0.55
            local ch = iconS * 0.85
            nvgBeginPath(vg)
            nvgRect(vg, icx - cw, icy - ch, cw * 2, ch * 2)
            nvgFillColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.18))
            nvgFill(vg)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.55))
            nvgStroke(vg)
            -- 符文竖线
            nvgBeginPath(vg)
            nvgMoveTo(vg, icx, icy - ch * 0.6)
            nvgLineTo(vg, icx, icy + ch * 0.6)
            nvgStrokeWidth(vg, 0.8)
            nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.50))
            nvgStroke(vg)
            nvgRestore(vg)
        end

        -- 汉字标签
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.75))
        nvgText(vg, ix + 14, row2Y, item.label)
        -- 数量
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.90))
        nvgText(vg, ix + 28, row2Y, "×" .. item.count)
        ix = ix + 62
    end

    -- 第三行：特殊道具（疾风符/迷雾残图/封印回响）
    local row3Y = barY + barH + 6
    self.itemButtons = {}
    local specialItems = {}

    -- 疾风符：可激活
    local rushCount = SessionState.getItemCount("rushWard")
    if rushCount > 0 or (self.rushWardTimer and self.rushWardTimer > 0) then
        table.insert(specialItems, {
            id = "rushWard", label = "疾风符",
            count = rushCount,
            active = self.rushWardTimer and self.rushWardTimer > 0,
            timer = self.rushWardTimer,
            color = P.jade,
            usable = rushCount > 0 and not (self.rushWardTimer and self.rushWardTimer > 0),
        })
    end

    -- 迷雾残图：被动（已生效标记）
    local fogCount = SessionState.getItemCount("fogMap")
    if fogCount > 0 or self.fogMapUsed then
        table.insert(specialItems, {
            id = "fogMap", label = "残图",
            count = fogCount,
            active = self.fogMapUsed,
            color = P.azure,
            usable = false,
        })
    end

    -- 兽目珠：主动使用
    local eyeCount = SessionState.getItemCount("beastEye")
    if eyeCount > 0 or (self.beastEyeTimer and self.beastEyeTimer > 0) then
        table.insert(specialItems, {
            id = "beastEye", label = "兽瞳",
            count = eyeCount,
            active = self.beastEyeTimer and self.beastEyeTimer > 0,
            timer = self.beastEyeTimer,
            color = P.gold,
            usable = eyeCount > 0 and not (self.beastEyeTimer and self.beastEyeTimer > 0),
        })
    end

    -- 封印回响：被动
    local echoCount = SessionState.getItemCount("sealEcho")
    if echoCount > 0 or SessionState.sealEchoUsed then
        table.insert(specialItems, {
            id = "sealEcho", label = "回响",
            count = echoCount,
            active = false,
            used = SessionState.sealEchoUsed,
            color = P.gold,
            usable = false,
        })
    end

    -- 灵泉丸：恢复道具
    local lqCount = SessionState.getItemCount("lingquanWan")
    local lqCasting = self.recoveryUsing and self.recoveryUsing.itemId == "lingquanWan"
    if lqCount > 0 or lqCasting then
        table.insert(specialItems, {
            id = "lingquanWan", label = "灵泉",
            count = lqCount,
            active = lqCasting,
            timer = lqCasting and self.recoveryUsing.timer or nil,
            color = P.azure,
            usable = lqCount > 0 and not self.recoveryUsing and not CombatSystem.collapsed
                and CombatSystem.hp < CombatSystem.MAX_HP,
        })
    end

    -- 绛珠露：恢复道具
    local jzCount = SessionState.getItemCount("jianzhulu")
    local jzCasting = self.recoveryUsing and self.recoveryUsing.itemId == "jianzhulu"
    if jzCount > 0 or jzCasting then
        table.insert(specialItems, {
            id = "jianzhulu", label = "绛珠",
            count = jzCount,
            active = jzCasting,
            timer = jzCasting and self.recoveryUsing.timer or nil,
            color = P.cinnabar,
            usable = jzCount > 0 and not self.recoveryUsing and not CombatSystem.collapsed
                and CombatSystem.hp < CombatSystem.MAX_HP,
        })
    end

    if #specialItems > 0 then
        local itemW = 70
        local itemH = 28
        local startX = barX + 8
        for idx, si in ipairs(specialItems) do
            local ix2 = startX + (idx - 1) * (itemW + 6)

            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix2, row3Y, itemW, itemH, 4)
            if si.active then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.15))
            elseif si.usable then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.08))
            else
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.06))
            end
            nvgFill(vg)

            -- 边框
            if si.usable then
                nvgStrokeWidth(vg, 1.0)
                nvgStrokeColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.5))
                nvgStroke(vg)
            end

            -- 标签
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labelAlpha = (si.active or si.usable) and 0.85 or 0.45
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, labelAlpha))
            nvgText(vg, ix2 + 6, row3Y + itemH * 0.5, si.label)

            -- 状态文字
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if si.active and si.timer and si.timer > 0 then
                -- 疾风符倒计时
                local secStr = string.format("%ds", math.ceil(si.timer))
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.9))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, secStr)
            elseif si.active and si.id == "fogMap" then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.65))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "已用")
            elseif si.used then
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.5))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "已用")
            elseif si.usable then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.7))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "使用")
            else
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.5))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "×" .. si.count)
            end

            -- 可点击区域
            if si.usable then
                table.insert(self.itemButtons, {
                    id = si.id,
                    x = ix2, y = row3Y, w = itemW, h = itemH,
                })
            end
        end
    end
end

------------------------------------------------------------
-- 操作区
------------------------------------------------------------

function ExploreScreen:renderControls(vg, logW, logH, t)
    local P = InkPalette

    -- 摇杆
    VirtualJoystick.draw(vg, logW, logH)

    -- 交互按钮（水墨风格：墨晕底 + 飞白描边弧 + 题款文字）
    if self.interactType then
        local btnX = logW * 0.78
        local btnY = logH * 0.88
        local btnR = 32

        -- 墨晕底色（取代标准圆填充）
        BrushStrokes.inkWash(vg, btnX, btnY, btnR * 0.15, btnR, P.jade, 0.18)

        -- 飞白描边弧（4段不连续弧线，模拟毛笔画圆）
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        for seg = 1, 4 do
            local startA = (seg - 1) * math.pi * 0.5 + 0.12
            local sweep = math.pi * 0.5 - 0.35  -- 留出飞白间隙
            nvgBeginPath(vg)
            nvgArc(vg, btnX, btnY, btnR * 0.88, startA, startA + sweep, NVG_CW)
            local w = 1.2 + (seg % 3) * 0.4
            nvgStrokeWidth(vg, w)
            nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.50 + seg * 0.04))
            nvgStroke(vg)
        end
        nvgRestore(vg)

        -- 题款式文字（略微偏移，模拟书法落款）
        local labels = {
            investigate = "调查",
            collect = "采集",
            suppress = "压制",
            evacuate = "撤离",
        }
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.8))
        nvgText(vg, btnX + 1, btnY + 1, labels[self.interactType] or "")
    end

    -- 调查进度条（调查进行中时显示）
    if self.investigateTarget and self.investigateDuration > 0 then
        local prog = math.min(1, self.investigateTimer / self.investigateDuration)
        local barW = logW * 0.35
        local barH = 6
        local barX = (logW - barW) * 0.5
        local barY = logH * 0.65
        -- 底框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35))
        nvgFill(vg)
        -- 填充
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * prog, barH, 3)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.75))
        nvgFill(vg)
        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
        nvgText(vg, logW * 0.5, barY - 3, "调查中...")
    end

    -- 撤离进度
    if EvacuationSystem.evacuating then
        local prog = EvacuationSystem.getProgress()
        local ep = EvacuationSystem.currentPoint
        if ep then
            local sx, sy = Camera.toScreen(ep.x, ep.y)
            nvgBeginPath(vg)
            nvgArc(vg, sx, sy, 20, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * prog, NVG_CW)
            nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.8))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end
    end

    -- 技能按钮（交互按钮左侧）
    self.skillBtn = nil  -- 重置每帧
    if SkillSystem.activeSkill then
        local skill = SkillSystem.SKILLS[SkillSystem.activeSkill]
        if skill then
            local skBtnX = logW * 0.60
            local skBtnY = logH * 0.88
            local skBtnR = 28
            local onCooldown = SkillSystem.cooldownTimer > 0
            local noUses = SkillSystem.usesLeft <= 0

            -- 墨晕底色
            local bgColor = onCooldown and P.inkLight or (noUses and P.inkWash or P.azure)
            local bgAlpha = (onCooldown or noUses) and 0.10 or 0.18
            BrushStrokes.inkWash(vg, skBtnX, skBtnY, skBtnR * 0.15, skBtnR, bgColor, bgAlpha)

            -- 飞白描边弧
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            local arcColor = (onCooldown or noUses) and P.inkLight or P.azure
            local arcAlpha = (onCooldown or noUses) and 0.25 or 0.55
            for seg = 1, 4 do
                local startA = (seg - 1) * math.pi * 0.5 + 0.12
                local sweep = math.pi * 0.5 - 0.35
                nvgBeginPath(vg)
                nvgArc(vg, skBtnX, skBtnY, skBtnR * 0.88, startA, startA + sweep, NVG_CW)
                nvgStrokeWidth(vg, 1.0 + (seg % 3) * 0.3)
                nvgStrokeColor(vg, nvgRGBAf(arcColor.r, arcColor.g, arcColor.b, arcAlpha))
                nvgStroke(vg)
            end
            nvgRestore(vg)

            -- 冷却遮罩（扇形灰色覆盖）
            if onCooldown then
                local cdMax = 1.5  -- 固定冷却时间约1.5s
                local cdProg = math.min(1, SkillSystem.cooldownTimer / cdMax)
                nvgBeginPath(vg)
                nvgMoveTo(vg, skBtnX, skBtnY)
                nvgArc(vg, skBtnX, skBtnY, skBtnR * 0.85,
                    -math.pi * 0.5,
                    -math.pi * 0.5 + math.pi * 2 * cdProg, NVG_CW)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.25))
                nvgFill(vg)
            end

            -- 技能图标符号（简化水墨符号）
            local iconSymbols = {
                lingfudan = "符", zhuijidan = "追", baoyanfu = "焰",
                fengyinzhen = "封", dingshenzou = "定", qusanfa = "散",
            }
            local sym = iconSymbols[SkillSystem.activeSkill] or "技"
            local textAlpha = (onCooldown or noUses) and 0.35 or 0.85
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, textAlpha))
            nvgText(vg, skBtnX, skBtnY - 2, sym)

            -- 剩余次数标注（右下角小数字）
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local countColor = noUses and P.cinnabar or P.inkMedium
            local countAlpha = noUses and 0.70 or 0.75
            nvgFillColor(vg, nvgRGBAf(countColor.r, countColor.g, countColor.b, countAlpha))
            nvgText(vg, skBtnX + skBtnR * 0.55, skBtnY + skBtnR * 0.55,
                tostring(SkillSystem.usesLeft))

            -- 保存按钮区域用于点击检测
            self.skillBtn = { x = skBtnX, y = skBtnY, r = skBtnR }
        end
    end

    -- 紧急逃脱按钮（collapse阶段 + 距撤离点>8格时显示）
    if self.emergencyEscapeAvailable then
        local ebW = 120
        local ebH = 36
        local ebX = (logW - ebW) * 0.5
        local ebY = logH * 0.58
        local pulse = 0.7 + math.sin(t * 4) * 0.2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, ebX, ebY, ebW, ebH, 6)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.20 * pulse))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.65 * pulse))
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.90 * pulse))
        nvgText(vg, logW * 0.5, ebY + ebH * 0.5, "紧急逃脱")

        self.emergencyEscapeBtn = { x = ebX, y = ebY, w = ebW, h = ebH }
    else
        self.emergencyEscapeBtn = nil
    end
end

------------------------------------------------------------
-- Toast 消息
------------------------------------------------------------

function ExploreScreen:renderToasts(vg, logW, logH, t)
    local P = InkPalette
    local baseY = logH * 0.35
    for i, toast in ipairs(self.toasts) do
        local alpha = math.min(1, toast.life / 0.5)
        local y = baseY + (i - 1) * 30
        InkRenderer.drawToast(vg, logW * 0.5, y, toast.text, alpha, logW)
    end
end

------------------------------------------------------------
-- 封灵器选择弹窗
------------------------------------------------------------

function ExploreScreen:renderSealerSelect(vg, logW, logH, t)
    local P = InkPalette
    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.5))
    nvgFill(vg)

    local list = self.sealerSelectList or {}
    local panelW = logW * 0.8
    local itemH = 52
    local panelH = #list * itemH + 80
    local panelX = (logW - panelW) * 0.5
    local panelY = (logH - panelH) * 0.5

    -- 面板底色
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.95))
    nvgFill(vg)
    BrushStrokes.inkRect(vg, panelX, panelY, panelW, panelH, P.inkMedium, 0.4, 99)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85))
    nvgText(vg, logW * 0.5, panelY + 24, "选择封灵器")

    -- 封灵器列表
    self.sealerSelectButtons = {}
    local beast = self.sealerSelectBeast
    local ambush = beast and beast.ambushBonus
    for i, info in ipairs(list) do
        local iy = panelY + 48 + (i - 1) * itemH
        local rate = info.rate
        if ambush then rate = math.min(1.0, rate + 0.20) end

        -- 行背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX + 10, iy, panelW - 20, itemH - 4, 4)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.06))
        nvgFill(vg)

        -- 名称 + 品级
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85))
        nvgText(vg, panelX + 24, iy + itemH * 0.35, info.name)

        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.7))
        nvgText(vg, panelX + 24, iy + itemH * 0.7,
            string.format("成功率 %d%%  库存 %d", math.floor(rate * 100), info.count))

        -- 选择按钮区域
        table.insert(self.sealerSelectButtons, {
            x = panelX + 10, y = iy, w = panelW - 20, h = itemH - 4,
            info = info,
        })
    end

    -- 取消按钮
    local cancelY = panelY + panelH - 30
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.6))
    nvgText(vg, logW * 0.5, cancelY, "取消（异兽将逃跑）")
    table.insert(self.sealerSelectButtons, {
        x = panelX, y = cancelY - 12, w = panelW, h = 24,
        info = nil,
    })
end

------------------------------------------------------------
-- 灵境传说卡片
------------------------------------------------------------

function ExploreScreen:renderRealmLegend(vg, logW, logH, t)
    local P = InkPalette
    local alpha = self.realmLegendAlpha
    local legend = self.realmLegend

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.55 * alpha))
    nvgFill(vg)

    -- 卡片尺寸
    local cardW = math.min(logW * 0.82, 320)
    local cardH = logH * 0.55
    local cardX = (logW - cardW) * 0.5
    local cardY = (logH - cardH) * 0.5

    -- 卡片底色（暖色宣纸）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.95 * alpha))
    nvgFill(vg)

    -- 飞白边框
    BrushStrokes.inkRect(vg, cardX, cardY, cardW, cardH, P.inkMedium, 0.45 * alpha, 77)

    -- 标题
    local cy = cardY + 32
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.90 * alpha))
    nvgText(vg, logW * 0.5, cy, legend.title or "灵境")

    -- 装饰线
    cy = cy + 22
    BrushStrokes.inkLine(vg, cardX + 30, cy, cardX + cardW - 30, cy,
        1.0, P.inkWash, 0.35 * alpha, 33)

    -- 正文（自动换行）
    cy = cy + 18
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.80 * alpha))
    local textX = cardX + 24
    local textW = cardW - 48
    local bounds = {}
    nvgTextBoxBounds(vg, textX, cy, textW, legend.text or "", bounds)
    nvgTextBox(vg, textX, cy, textW, legend.text or "")

    -- 提示语
    local textBottom = bounds[4] or (cy + 60)
    local hintY = textBottom + 20
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.65 * alpha))
    nvgTextBox(vg, cardX + 24, hintY, textW, legend.hint or "")

    -- 底部提示
    local tipAlpha = (0.4 + math.sin(t * 2.5) * 0.15) * alpha
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, tipAlpha))
    nvgText(vg, logW * 0.5, cardY + cardH - 12, "点击任意处继续")
end

------------------------------------------------------------
-- HP 血条（10滴水墨滴）
------------------------------------------------------------

function ExploreScreen:renderHPBar(vg, logW, logH, t)
    local P = InkPalette
    local hp = CombatSystem.hp
    local maxHP = CombatSystem.MAX_HP

    local startX = 12
    local startY = logH * 0.04 + 8
    local dropSpacing = 14
    local dropR = 5

    for i = 1, maxHP do
        local cx = startX + (i - 1) * dropSpacing
        local cy = startY

        if i <= hp then
            -- 有血：朱砂实心滴
            local alive = true
            -- ≤3滴时闪烁预警
            if hp <= 3 then
                local blink = math.sin(t * 6 + i * 0.5)
                if blink < -0.3 then alive = false end
            end

            if alive then
                -- 水滴形状（圆 + 顶部尖角）
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy + 1, dropR)
                nvgMoveTo(vg, cx - dropR * 0.5, cy - dropR * 0.3)
                nvgLineTo(vg, cx, cy - dropR * 1.4)
                nvgLineTo(vg, cx + dropR * 0.5, cy - dropR * 0.3)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.85))
                nvgFill(vg)
            else
                -- 闪烁暗态
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy + 1, dropR)
                nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.25))
                nvgFill(vg)
            end
        else
            -- 无血：灰色空心滴
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy + 1, dropR * 0.8)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35))
            nvgStroke(vg)
        end
    end
end

------------------------------------------------------------
-- 小地图
------------------------------------------------------------

local MINIMAP_COLORS = {
    grass  = { 0.45, 0.55, 0.35 },
    path   = { 0.65, 0.58, 0.45 },
    rock   = { 0.50, 0.48, 0.45 },
    bamboo = { 0.30, 0.48, 0.30 },
    water  = { 0.30, 0.40, 0.60 },
    danger = { 0.50, 0.25, 0.35 },
    wall   = { 0.12, 0.10, 0.08 },
}

function ExploreScreen:renderMinimap(vg, logW, logH, t)
    local map = self.map
    if not map then return end

    local expanded = self.minimapExpanded
    local scale, mx, my, mw, mh

    if expanded then
        scale = math.min((logW * 0.65) / map.width, (logH * 0.60) / map.height)
        mw = map.width * scale
        mh = map.height * scale
        mx = (logW - mw) * 0.5
        my = (logH - mh) * 0.5
    else
        scale = math.min(2.5, (logW * 0.22) / map.width)
        mw = map.width * scale
        mh = map.height * scale
        mx = logW - mw - 10
        my = 55
    end

    self.minimapBounds = { x = mx, y = my, w = mw, h = mh }

    -- 展开时暗化背景
    if expanded then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.55))
        nvgFill(vg)
    end

    -- 地图底框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx - 2, my - 2, mw + 4, mh + 4, 3)
    nvgFillColor(vg, nvgRGBAf(0.06, 0.05, 0.04, 0.9))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(0.3, 0.25, 0.2, 0.5))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 绘制瓦片
    for ty = 1, map.height do
        for tx = 1, map.width do
            local tile = map.tiles[ty][tx]
            local fogState = FogOfWar.getState(tx - 1, ty - 1)
            if fogState ~= FogOfWar.DARK then
                local col = MINIMAP_COLORS[tile.type] or MINIMAP_COLORS.wall
                local alpha = fogState == FogOfWar.VISIBLE and 0.9 or 0.4
                nvgBeginPath(vg)
                -- y=1 是底部(出生点)，在小地图最下方
                local sy = my + (map.height - ty) * scale
                nvgRect(vg, mx + (tx - 1) * scale, sy, scale + 0.5, scale + 0.5)
                nvgFillColor(vg, nvgRGBAf(col[1], col[2], col[3], alpha))
                nvgFill(vg)
            end
        end
    end

    -- 实体标记
    if expanded then
        -- 撤离点
        for _, ep in ipairs(map.evacuationPoints) do
            local fs = FogOfWar.getState(ep.x, ep.y)
            if fs ~= FogOfWar.DARK then
                local ex = mx + ep.x * scale + scale * 0.5
                local ey = my + (map.height - 1 - ep.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, ex, ey, scale * 1.2)
                nvgFillColor(vg, nvgRGBAf(0.2, 0.6, 0.9, 0.85))
                nvgFill(vg)
            end
        end
        -- 资源
        for _, res in ipairs(map.resources) do
            if not res.collected then
                local fs = FogOfWar.getState(res.x, res.y)
                if fs ~= FogOfWar.DARK then
                    local rx = mx + res.x * scale + scale * 0.5
                    local ry = my + (map.height - 1 - res.y) * scale + scale * 0.5
                    nvgBeginPath(vg)
                    nvgCircle(vg, rx, ry, scale * 0.5)
                    nvgFillColor(vg, nvgRGBAf(0.3, 0.7, 0.3, fs == FogOfWar.VISIBLE and 0.8 or 0.4))
                    nvgFill(vg)
                end
            end
        end
        -- 异兽（仅可见区域）
        for _, beast in ipairs(self.beasts) do
            if beast.aiState ~= "captured" and FogOfWar.isEntityVisible(beast.x, beast.y) then
                local bx = mx + beast.x * scale + scale * 0.5
                local by = my + (map.height - 1 - beast.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, bx, by, scale * 0.7)
                nvgFillColor(vg, nvgRGBAf(0.8, 0.2, 0.15, 0.85))
                nvgFill(vg)
            end
        end
    else
        -- 折叠模式：只显示撤离点
        for _, ep in ipairs(map.evacuationPoints) do
            local fs = FogOfWar.getState(ep.x, ep.y)
            if fs ~= FogOfWar.DARK then
                local ex = mx + ep.x * scale + scale * 0.5
                local ey = my + (map.height - 1 - ep.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, ex, ey, 2.5)
                nvgFillColor(vg, nvgRGBAf(0.2, 0.6, 0.9, 0.9))
                nvgFill(vg)
            end
        end
    end

    -- 玩家标记（始终显示）
    local px = mx + self.playerX * scale + scale * 0.5
    local py = my + (map.height - 1 - self.playerY) * scale + scale * 0.5
    local dotR = expanded and 4.5 or 2.5
    -- 光晕
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, dotR + 2)
    nvgFillColor(vg, nvgRGBAf(1, 0.85, 0.3, 0.3 + math.sin(t * 4) * 0.15))
    nvgFill(vg)
    -- 核心
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, dotR)
    nvgFillColor(vg, nvgRGBAf(1, 0.9, 0.35, 1))
    nvgFill(vg)

    -- 折叠模式标题
    if not expanded then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(0.6, 0.55, 0.5, 0.7))
        nvgText(vg, mx + mw * 0.5, my + mh + 3, "[ 点击展开 ]")
    end
end

return ExploreScreen
