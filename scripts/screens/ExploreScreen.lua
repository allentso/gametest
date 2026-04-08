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
local EventBus = require("systems.EventBus")
local ScreenManager = require("systems.ScreenManager")
local TutorialSystem = require("systems.TutorialSystem")
local BrushStrokes = require("render.BrushStrokes")
local InkTileRenderer = require("render.InkTileRenderer")
local InkRenderer = require("render.InkRenderer")
local BeastRenderer = require("render.BeastRenderer")

-- 资源拼音→中文名映射
local RES_NAMES = {
    lingshi = "灵石", shouhun = "兽魂", tianjing = "天晶",
    traceAsh = "追迹灰", mirrorSand = "镇灵砂", soulCharm = "归魂符",
}

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

    return self
end

function ExploreScreen:onEnter()
    -- 重置单局状态
    SessionState.reset()

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

    -- 墨迹更新
    for i = #self.inkPatches, 1, -1 do
        self.inkPatches[i].life = self.inkPatches[i].life - dt
        if self.inkPatches[i].life <= 0 then
            table.remove(self.inkPatches, i)
        end
    end

    -- 迷雾更新（竹林中视野缩减至3格，噬天被动+1格）
    local visionRadius = Config.VISION_RADIUS
    if self.playerInBamboo then visionRadius = 3.0 end
    if self:hasCapturedBeast("002") then visionRadius = visionRadius + 1 end
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

    -- 瘴气地形每秒消耗1灵石
    if tileType == "danger" then
        self.dangerDrainTimer = (self.dangerDrainTimer or 0) + dt
        if self.dangerDrainTimer >= 1.0 then
            self.dangerDrainTimer = self.dangerDrainTimer - 1.0
            local currentLingshi = SessionState.getResource("lingshi")
            if currentLingshi > 0 then
                SessionState.addResource("lingshi", -1)
                self:addToast("瘴气侵蚀 -1灵石")
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
    if TrackingSystem.clueCount >= 5 then
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
            if dist < 1.5 then
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
    for _, clue in ipairs(self.map.clues) do
        if not clue.investigated then
            local dx = clue.x - self.playerX
            local dy = clue.y - self.playerY
            if math.sqrt(dx * dx + dy * dy) < 1.2 then
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
            if math.sqrt(dx * dx + dy * dy) < 1.2 then
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
        local SuppressOverlay = require("screens.SuppressOverlay")
        ScreenManager.push(SuppressOverlay, { beast = beast })
        TutorialSystem.checkTrigger("suppress")

    elseif self.interactType == "investigate" then
        local clue = self.interactTarget
        local hasTraceAsh = SessionState.hasItem("traceAsh")
        if hasTraceAsh then
            SessionState.addItem("traceAsh", -1)
        end
        TrackingSystem.investigate(clue, hasTraceAsh)
        SessionState.stats.cluesInvestigated = SessionState.stats.cluesInvestigated + 1
        self:addToast("发现线索！")
        TutorialSystem.checkTrigger("investigate")

        -- 高危区线索每日任务
        local py = math.floor(self.playerY)
        if py / Config.MAP_HEIGHT > 0.7 then
            EventBus.emit("danger_clue_investigated")
        end

    elseif self.interactType == "collect" then
        local res = self.interactTarget
        res.collected = true
        -- 区分会话资源和跨局资源
        if res.type == "lingshi" or res.type == "shouhun" or res.type == "tianjing" then
            SessionState.addResource(res.type, res.amount)
        else
            SessionState.addItem(res.type, res.amount)
        end
        self:addToast("获得 " .. (RES_NAMES[res.type] or res.type) .. " ×" .. res.amount)
        TutorialSystem.checkTrigger("collect")

    elseif self.interactType == "evacuate" then
        if not EvacuationSystem.evacuating then
            -- 检查特殊撤离条件
            local hasTuou = false
            for _, c in ipairs(SessionState.getContracts()) do
                if c.beastId == "008" then hasTuou = true; break end
            end
            EvacuationSystem.startEvacuation(self.interactTarget, {
                hasTuou = hasTuou,
                isCollapse = Timer.phase == "collapse",
                hasRushWard = self.rushWardTimer and self.rushWardTimer > 0,
            })
            TutorialSystem.checkTrigger("evacuate")
        end
    end
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
        -- 压制失败：检查封印回响
        if SessionState.hasItem("sealEcho") and not SessionState.sealEchoUsed then
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
    local unstable = EvacuationSystem.checkContractStability(contracts, soulCharmCount, hasIceSilk)
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

function ExploreScreen:goToResult(lostContracts)
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

    self:goToResult(lostContracts)
end

--- 检查本局是否已捕获某种异兽（用于被动效果判定）
function ExploreScreen:hasCapturedBeast(beastId)
    for _, c in ipairs(SessionState.getContracts()) do
        if c.beastId == beastId then return true end
    end
    return false
end

function ExploreScreen:addToast(msg)
    table.insert(self.toasts, { text = msg, life = 2.5, maxLife = 2.5 })
end

------------------------------------------------------------
-- 输入
------------------------------------------------------------

function ExploreScreen:onInput(action, sx, sy)
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

    -- 资源
    for _, res in ipairs(self.map.resources) do
        if not res.collected and FogOfWar.isEntityVisible(res.x, res.y) then
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
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            if FogOfWar.isEntityVisible(beast.x, beast.y) and Camera.inView(beast.x, beast.y) then
                local sx, sy = Camera.toScreen(beast.x, beast.y)
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

return ExploreScreen
