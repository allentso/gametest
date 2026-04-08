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

    return self
end

function ExploreScreen:onEnter()
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

    -- 新手引导
    TutorialSystem.start()
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
    -- 生成 3-5 只 R 级异兽
    local count = 3 + math.random(0, 2)
    for i = 1, count do
        local beastInfo = BeastData.getRandom()
        local x, y = self:findOpenPosition(4, self.map.height - 2)
        if x then
            local beast = BeastAI.createBeast(beastInfo, x, y, "R")
            table.insert(self.beasts, beast)
        end
    end
end

function ExploreScreen:spawnTrackedBeast(quality)
    -- 在玩家附近 6-10 格外生成追踪到的异兽
    local beastInfo = BeastData.getRandom()
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

    -- 迷雾更新
    FogOfWar.update(self.playerX, self.playerY)

    -- 相机跟随
    Camera.follow(self.playerX, self.playerY, dt)

    -- 异兽 AI
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "suppress" then
            BeastAI.update(beast, dt, self.playerX, self.playerY, self.map)
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

    if self.playerMoving then
        local speed = Config.PLAYER_SPEED
        local moveX = dx * speed * dt
        local moveY = dy * speed * dt
        -- CollisionSystem 直接修改传入对象的 x/y，使用 proxy 读回结果
        local proxy = { x = self.playerX, y = self.playerY, halfW = 0.3, halfH = 0.3 }
        CollisionSystem.tryMove(proxy, moveX, moveY, self.map)
        self.playerX = proxy.x
        self.playerY = proxy.y
        self.playerFacing = math.atan2(dy, dx)

        -- 添加行迹
        if math.random() < 0.3 then
            table.insert(self.playerTrails, {
                x = self.playerX, y = self.playerY,
                life = 0.3, maxLife = 0.3,
                alpha = 0.2 + math.random() * 0.1,
            })
        end

        -- 撤离中移动则取消
        if EvacuationSystem.evacuating then
            EvacuationSystem.cancel()
        end
    end

    -- 边界限制
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
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            local dist = BeastAI.distTo(beast, self.playerX, self.playerY)
            if dist < 1.5 then
                local contactType = BeastAI.getContactType(beast, self.playerX, self.playerY)
                if contactType == "back" then
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
        -- 检查偷袭
        local contactType = BeastAI.getContactType(beast, self.playerX, self.playerY)
        if contactType == "back" then
            beast.ambushBonus = true
        end
        local hasMirrorSand = SessionState.hasItem("mirrorSand")
        if hasMirrorSand then
            SessionState.addItem("mirrorSand", -1)
        end
        SuppressSystem.start(beast, hasMirrorSand)
        -- 推入 SuppressOverlay
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

    elseif self.interactType == "collect" then
        local res = self.interactTarget
        res.collected = true
        -- 区分会话资源和跨局资源
        if res.type == "lingshi" or res.type == "shouhun" or res.type == "tianjing" then
            SessionState.addResource(res.type, res.amount)
        else
            SessionState.addItem(res.type, res.amount)
        end
        self:addToast("获得 " .. res.type .. " ×" .. res.amount)
        TutorialSystem.checkTrigger("collect")

    elseif self.interactType == "evacuate" then
        if not EvacuationSystem.evacuating then
            EvacuationSystem.startEvacuation(self.interactTarget)
            TutorialSystem.checkTrigger("evacuate")
        end
    end
end

function ExploreScreen:onSuppressResult(result)
    if not self.activeBeast then return end
    if result == "success" then
        -- 压制成功，进入捕获判定
        local beast = self.activeBeast
        local tier, key = CaptureSystem.selectBestSealer(SessionState.inventory)
        if tier then
            local contract = CaptureSystem.attemptCapture(beast, tier, SessionState.inventory, key)
            if contract then
                beast.aiState = "captured"
                -- 推入 CaptureOverlay
                local CaptureOverlay = require("screens.CaptureOverlay")
                ScreenManager.push(CaptureOverlay, {
                    beast = beast,
                    contract = contract,
                })
            end
        else
            self:addToast("没有封灵器！")
            self.activeBeast.aiState = "flee"
        end
    else
        self:addToast("压制失败！")
        self.activeBeast.aiState = "flee"
    end
    self.activeBeast = nil
end

function ExploreScreen:onEvacuationComplete()
    -- 检查灵契稳定性
    local contracts = SessionState.getContracts()
    if #contracts == 0 then
        -- 无灵契直接结算
        self:goToResult({})
        return
    end
    local soulCharmCount = SessionState.getItemCount("soulCharm")
    local unstable = EvacuationSystem.checkContractStability(contracts, soulCharmCount)
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
    -- 时间到，所有灵契不稳定
    self:goToResult(SessionState.getContracts())
end

function ExploreScreen:addToast(msg)
    table.insert(self.toasts, { text = msg, life = 2.5, maxLife = 2.5 })
end

------------------------------------------------------------
-- 输入
------------------------------------------------------------

function ExploreScreen:onInput(action, sx, sy)
    if self.paused then return false end

    if action == "down" then
        -- 交互按钮检测（优先于摇杆）
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
            if tile and tile.type ~= "wall" then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    -- 坐标抖动：打破网格死板感
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
            if tile and tile.type ~= "wall" then
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

    -- 异兽
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            if FogOfWar.isEntityVisible(beast.x, beast.y) and Camera.inView(beast.x, beast.y) then
                local sx, sy = Camera.toScreen(beast.x, beast.y)
                BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
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

    -- 第二行：本局道具（墨点色标 + 汉字标签 + 数量）
    local row2Y = barY + barH * 0.74
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local items = {
        { label = "灰", count = SessionState.getItemCount("traceAsh"), color = P.inkMedium },
        { label = "砂", count = SessionState.getItemCount("mirrorSand"), color = P.azure },
        { label = "符", count = SessionState.getItemCount("soulCharm"), color = P.gold },
    }
    local ix = barX + 14
    for idx, item in ipairs(items) do
        -- 色标：不规则墨点（加大到 5px）
        BrushStrokes.inkDotStable(vg, ix, row2Y, 5, item.color, 0.65, idx * 29)
        -- 汉字标签
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.70))
        nvgText(vg, ix + 8, row2Y, item.label)
        -- 数量
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85))
        nvgText(vg, ix + 22, row2Y, "×" .. item.count)
        ix = ix + 58
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
        local alpha = math.min(1, toast.life / 0.5) -- 淡出
        local y = baseY + (i - 1) * 30
        InkRenderer.drawToast(vg, logW * 0.5, y, toast.text, alpha, logW)
    end
end

return ExploreScreen
