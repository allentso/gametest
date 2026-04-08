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
local TutorialSystem = require("systems.TutorialSystem")
local BrushStrokes = require("render.BrushStrokes")
local InkTileRenderer = require("render.InkTileRenderer")
local InkRenderer = require("render.InkRenderer")
local BeastRenderer = require("render.BeastRenderer")

-- 资源拼音→中文名映射
local RES_NAMES = {
    lingshi = "灵石", shouhun = "兽魂", tianjing = "天晶", lingyin = "灵印",
    traceAsh = "追迹灰", mirrorSand = "镇灵砂", soulCharm = "归魂符",
    beastEye = "兽瞳", sealEcho = "封印回响",
}

local LoreData = require("data.LoreData")

------------------------------------------------------------
-- 流派层级效果定义（3层：初学/精通/大成）
------------------------------------------------------------
local SCHOOL_EFFECTS = {
    trace = {
        { name = "初学·追迹", desc = "调查线索速度+15%",       clueSpeedMul = 1.15 },
        { name = "精通·追迹", desc = "调查速度+25%，线索可见距离+1", clueSpeedMul = 1.25, clueVision = 1 },
        { name = "大成·追迹", desc = "调查速度+40%，SSR线索需求-1，闪光+10%，兽目珠30秒", clueSpeedMul = 1.40, clueVision = 1, ssrReduce = 1, flashBonus = 0.10, beastEyeDuration = 30 },
    },
    suppress = {
        { name = "初学·压制", desc = "QTE速度降低10%",         qteSpeedMul = 0.90 },
        { name = "精通·压制", desc = "QTE速度降低20%，目标区+10%", qteSpeedMul = 0.80, qteZoneMul = 1.10 },
        { name = "大成·压制", desc = "QTE速度降低30%，失败可重试1次", qteSpeedMul = 0.70, qteZoneMul = 1.10, qteRetry = 1 },
    },
    evac = {
        { name = "初学·撤离", desc = "撤离时间-0.5s",          evacTimeSave = 0.5 },
        { name = "精通·撤离", desc = "撤离时间-1s，灵契保护1只",  evacTimeSave = 1.0, contractProtect = 1 },
        { name = "大成·撤离", desc = "撤离时间-1.5s，紧急逃脱无损失", evacTimeSave = 1.5, contractProtect = 1, safeEscape = true },
    },
    greed = {
        { name = "初学·贪渊", desc = "高危区资源产出+20%",      dangerResMul = 1.20 },
        { name = "精通·贪渊", desc = "资源产出+30%，瘴气消耗减半", dangerResMul = 1.30, dangerDrainHalf = true },
        { name = "大成·贪渊", desc = "资源产出+50%，瘴气免疫",   dangerResMul = 1.50, dangerImmune = true },
    },
}

--- 获取当前流派层级 (0=无/1=初学/2=精通/3=大成)
--- 需同时满足：使用次数达标 AND 封灵师境界达标
local function getSchoolTier()
    local school = SessionState.selectedSchool
    if not school then return 0 end
    local progress = GameState.data.schoolProgress[school] or 0
    local level = GameState.getSealerLevel()

    -- 大成：使用10次 + 境界5
    if progress >= 10 and level >= 5 then return 3
    -- 精通：使用5次 + 境界3
    elseif progress >= 5 and level >= 3 then return 2
    -- 初学：使用1次（默认解锁）
    elseif progress >= 1 then return 1
    else return 0 end
end

--- 获取当前流派效果表（nil 表示无效果）
local function getSchoolEffect()
    local school = SessionState.selectedSchool
    if not school then return nil end
    local tier = getSchoolTier()
    if tier == 0 then return nil end
    local effects = SCHOOL_EFFECTS[school]
    return effects and effects[tier] or nil
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

    -- 墨鸦墨迹系统
    self.inkPatches = {}

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
        self:addToast("捕获成功！" .. contract.name)
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

    -- 流派追迹大成：SSR线索需求-1 + 闪光概率+10%
    local effect = getSchoolEffect()
    if effect and effect.ssrReduce then
        TrackingSystem.ssrReduceBonus = effect.ssrReduce
    end
    if effect and effect.flashBonus then
        TrackingSystem.schoolFlashBonus = effect.flashBonus
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

    -- 特殊道具 HUD 按钮状态
    self.itemButtons = {}

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
        and BeastData.getRandomForBiome(biome)
        or BeastData.getRandom()
    local angle = math.random() * math.pi * 2
    local dist = 6 + math.random() * 4
    local tx = self.playerX + math.cos(angle) * dist
    local ty = self.playerY + math.sin(angle) * dist
    tx = math.max(2, math.min(Config.MAP_WIDTH - 3, tx))
    ty = math.max(2, math.min(Config.MAP_HEIGHT - 3, ty))

    local beast = BeastAI.createBeast(beastInfo, tx, ty, quality)
    beast.aiState = "wander"
    table.insert(self.beasts, beast)
    self:addToast(quality .. "级异兽出现！")
    TutorialSystem.checkTrigger("beast_spawned")
end

function ExploreScreen:findOpenPosition(minY, maxY)
    for attempt = 1, 30 do
        local x = math.random(3, Config.MAP_WIDTH - 3)
        local y = math.random(minY, maxY)
        if not self.map:isBlocked(x, y) then
            return x, y
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

    -- 迷雾更新（竹林中视野缩减至3格，噬天被动+1格，追迹流派+视距）
    local visionRadius = Config.VISION_RADIUS
    if self.playerInBamboo then visionRadius = 3.0 end
    if self:hasCapturedBeast("002") then visionRadius = visionRadius + 1 end
    local effect = getSchoolEffect()
    if effect and effect.clueVision then
        visionRadius = visionRadius + effect.clueVision
    end
    -- 墨鸦墨迹区域降低视野
    for _, patch in ipairs(self.inkPatches) do
        local pdx = self.playerX - patch.x
        local pdy = self.playerY - patch.y
        if pdx * pdx + pdy * pdy < 4 then
            visionRadius = math.min(visionRadius, 1.0)
            break
        end
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

    -- 瘴气地形每秒消耗1灵石（贪渊流派可减免）
    if tileType == "danger" then
        local greedEffect = getSchoolEffect()
        local dangerImmune = greedEffect and greedEffect.dangerImmune
        if not dangerImmune then
            local drainInterval = 1.0
            if greedEffect and greedEffect.dangerDrainHalf then
                drainInterval = 2.0
            end
            self.dangerDrainTimer = (self.dangerDrainTimer or 0) + dt
            if self.dangerDrainTimer >= drainInterval then
                self.dangerDrainTimer = self.dangerDrainTimer - drainInterval
                -- 灾变期(danger/collapse)瘴气伤害加倍
                local drainAmount = 1
                if Timer.phase == "danger" or Timer.phase == "collapse" then
                    drainAmount = 2
                end
                local currentLingshi = SessionState.getResource("lingshi")
                if currentLingshi > 0 then
                    local actual = math.min(drainAmount, currentLingshi)
                    SessionState.addResource("lingshi", -actual)
                    if drainAmount > 1 then
                        self:addToast("瘴气猛烈侵蚀 -" .. actual .. "灵石")
                    else
                        self:addToast("瘴气侵蚀 -1灵石")
                    end
                end
            end
        end
    else
        self.dangerDrainTimer = 0
    end

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
        -- 水蛟被动：水面地形移速+20%
        if tileType == "water" and self:hasCapturedBeast("006") then
            speed = speed * 1.2
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
           and beast.aiState ~= "petrified" and beast.aiState ~= "burst" then
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

    -- 2. 检测线索（玄狐被动：检测范围+0.4）
    local clueRange = 1.2
    if self:hasCapturedBeast("001") then clueRange = clueRange + 0.4 end
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
        -- 水蛟水面QTE加速标记
        if beast.id == "006" and BeastAI.isNearWater(beast, self.map) then
            beast.nearWaterQTE = true
        end
        SuppressSystem.start(beast, hasMirrorSand)
        -- 水蛟水面附近QTE指针加速×1.2
        if beast.nearWaterQTE then
            SuppressSystem.state.speed = SuppressSystem.state.speed * 1.2
        end
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
            -- 检查特殊撤离条件
            local hasTuou = false
            for _, c in ipairs(SessionState.getContracts()) do
                if c.beastId == "008" then hasTuou = true; break end
            end
            local eEffect = getSchoolEffect()
            EvacuationSystem.startEvacuation(self.interactTarget, {
                hasTuou = hasTuou,
                isCollapse = Timer.phase == "collapse",
                hasRushWard = self.rushWardTimer and self.rushWardTimer > 0,
                schoolTimeSave = eEffect and eEffect.evacTimeSave or 0,
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
            -- 石灵压制失败→石化防御5秒
            if self.activeBeast.id == "005" then
                BeastAI.enterPetrify(self.activeBeast)
                self:addToast("石灵进入石化防御！")
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
    -- 检查冰蚕被动效果
    local hasIceSilk = false
    for _, c in ipairs(contracts) do
        if c.beastId == "009" then hasIceSilk = true; break end
    end
    -- 流派撤离保护
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
    end
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

    if self.paused then return false end

    if action == "down" then
        -- 紧急逃脱按钮
        if self.emergencyEscapeBtn then
            local eb = self.emergencyEscapeBtn
            if sx >= eb.x and sx <= eb.x + eb.w
               and sy >= eb.y and sy <= eb.y + eb.h then
                self:doEmergencyEscape()
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
    self:renderToasts(vg, logW, logH, t)

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

    -- 资源（石灵被动：资源可透雾显示）
    local resSeeThroughFog = self:hasCapturedBeast("005")
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

    -- 墨鸦墨迹区域
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
            local eyeRevealed = beastEyeActive and Camera.inView(beast.x, beast.y) and not beast.invisible
            if normalVisible or eyeRevealed then
                local sx, sy = Camera.toScreen(beast.x, beast.y)
                -- 兽目珠揭示（非正常视野）：金色灵光标记
                if eyeRevealed and not normalVisible then
                    local pulseR = ppu * beast.bodySize * 1.5 + math.sin(t * 4) * ppu * 0.1
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, pulseR)
                    nvgStrokeColor(vg, nvgRGBAf(0.85, 0.70, 0.20, 0.4 + math.sin(t * 3) * 0.15))
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end
                if beast.invisible then
                    -- 风鸣隐形：仅显示草叶扰动粒子
                    for pi = 1, 3 do
                        local px = sx + math.sin(t * 2 + pi * 2.1) * ppu * 0.4
                        local py = sy + math.cos(t * 1.5 + pi * 1.7) * ppu * 0.3
                        local pa = 0.15 + math.sin(t * 3 + pi) * 0.08
                        nvgBeginPath(vg)
                        nvgCircle(vg, px, py, 2)
                        nvgFillColor(vg, nvgRGBAf(0.3, 0.5, 0.2, pa))
                        nvgFill(vg)
                    end
                elseif beast.aiState == "petrified" then
                    -- 石灵石化：灰色外框
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, ppu * beast.bodySize * 1.2)
                    nvgStrokeColor(vg, nvgRGBAf(0.5, 0.5, 0.5, 0.5))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                else
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                end
            end
        end
    end

    -- 玩家（始终绘制在最上层）
    local psx, psy = Camera.toScreen(self.playerX, self.playerY)
    InkRenderer.drawPlayer(vg, psx, psy, ppu, self.playerFacing, t)

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

return ExploreScreen
