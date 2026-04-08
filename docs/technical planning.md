# 《山海异闻录：寻光》技术方案

> **引擎**: UrhoX（Lua 5.4）
> **渲染**: NanoVG（矢量绘图）+ urhox-libs/UI（Yoga Flexbox + NanoVG）
> **屏幕**: 竖屏 Portrait
> **分辨率**: 模式 B（`logW = physW/dpr, logH = physH/dpr`）
> **性能目标**: 骁龙 665 级别 60fps
> **策划详情**: 见 game Planning.md
> **视觉规格**: 见 ui.md

---

## 一、总体架构

### 1.1 技术栈

| 模块 | 方案 |
|------|------|
| 引擎 | UrhoX（Lua 5.4） |
| 2D 渲染 | NanoVG（矢量，NanoVGRender 事件） |
| UI | urhox-libs/UI（Yoga Flexbox + NanoVG） |
| 存档 | File + cjson（沙箱化路径） |
| 计时 | Update 事件 dt 累加 |
| 贴图 | nvgCreateImage（可选增强，程序化为主） |

### 1.2 核心架构决策

- **渲染**: NanoVG 矢量渲染（StaticSprite2D 方案已验证不可用——CDN 路径不兼容）
- **坐标系**: 统一世界坐标（Y-up），Camera 模块做唯一转换
- **存档**: 三文件分离（main/pity/session），保底计数带 HMAC 校验
- **碰撞**: 分轴碰撞 + 角落滑动
- **UI**: 手动 Tab 实现（绕过 UI.Tabs 组件缺陷）

### 1.3 渲染层级架构

```
┌──────────────────────────────────────┐
│  Layer 5: 模态叠层（压制QTE/捕获演出/  │  吞掉所有输入
│           灵契QTE/结算卷轴/新手引导）  │
├──────────────────────────────────────┤
│  Layer 4: HUD + 特效层               │  倒计时/底部信息条/Toast/
│           NanoVG + urhox-libs/UI     │  氛围粒子/灾变瘴气暗角
├──────────────────────────────────────┤
│  Layer 3: 迷雾层（NanoVG）            │  战争迷雾遮罩（径向渐变）
├──────────────────────────────────────┤
│  Layer 2: 实体层（NanoVG）            │  异兽/玩家/线索/资源/撤离点
├──────────────────────────────────────┤
│  Layer 1: 世界层（NanoVG）            │  宣纸底 + 水墨瓦片（无格线）
└──────────────────────────────────────┘
```

### 1.4 竖屏布局比例

| 区域 | 屏幕占比 | 内容 |
|------|---------|------|
| 顶部 HUD | ~6% | 倒计时（36px）+ 阶段名 |
| 主游戏区 | ~69% | 地图 + 迷雾 + 实体 |
| 底部信息 | ~8% | 线索进度 + 本局道具 + 灵契印章 |
| 操作区 | ~17% | 虚拟摇杆（左下）+ 交互按钮（右下） |

---

## 二、坐标系统

### 2.1 全局约定

项目内只存在一套坐标系，所有逻辑在世界坐标完成，渲染时通过 `Camera` 一次性转换。

```
世界坐标 (World Space)         屏幕坐标 (Screen Space)
  原点: 地图左下角               原点: 屏幕左上角
  X: 向右为正                    X: 向右为正
  Y: 向上为正                    Y: 向下为正
  单位: 逻辑格（1格=1 unit）      单位: 逻辑像素（physW/dpr × physH/dpr）
```

### 2.2 Camera.lua

```lua
local Camera = {}

Camera.x = 0
Camera.y = 0
Camera.viewH = 10       -- 竖屏可见世界高度
Camera.ppu = 0           -- 运行时计算: logH / viewH
Camera.logW = 0
Camera.logH = 0

function Camera.resize(logW, logH)
    Camera.logW = logW
    Camera.logH = logH
    Camera.ppu = logH / Camera.viewH
end

function Camera.toScreen(wx, wy)
    local sx = (wx - Camera.x) * Camera.ppu + Camera.logW * 0.5
    local sy = Camera.logH * 0.5 - (wy - Camera.y) * Camera.ppu
    return sx, sy
end

function Camera.toWorld(sx, sy)
    local wx = (sx - Camera.logW * 0.5) / Camera.ppu + Camera.x
    local wy = (Camera.logH * 0.5 - sy) / Camera.ppu + Camera.y
    return wx, wy
end

function Camera.follow(targetX, targetY, dt)
    local lerp = 1 - math.exp(-5.0 * dt)
    Camera.x = Camera.x + (targetX - Camera.x) * lerp
    Camera.y = Camera.y + (targetY - Camera.y) * lerp
end

function Camera.inView(wx, wy, margin)
    margin = margin or 1
    local halfW = (Camera.logW / Camera.ppu) * 0.5 + margin
    local halfH = Camera.viewH * 0.5 + margin
    return math.abs(wx - Camera.x) < halfW and math.abs(wy - Camera.y) < halfH
end

return Camera
```

---

## 三、基础设施模块

### 3.1 EventBus.lua — 事件总线

```lua
local EventBus = {}
local listeners = {}

function EventBus.on(event, fn, owner)
    if not listeners[event] then listeners[event] = {} end
    table.insert(listeners[event], { fn = fn, owner = owner })
end

function EventBus.off(event, owner)
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
```

**核心事件表**:

| 事件名 | 发送方 | 数据 | 监听方 |
|--------|--------|------|--------|
| `phase_changed` | Timer | phase, remaining | ExploreScreen, AudioMgr |
| `beast_spawned` | ExploreLogic | beast | ExploreScreen |
| `beast_captured` | CaptureSystem | beast（含 quality） | SessionState, BookScreen, PitySystem |
| `capture_failed` | CaptureSystem | beast | BeastAI（转警觉态） |
| `clue_collected` | TrackingSystem | clueType, count | HUD, ExploreLogic |
| `beast_spawn_request` | TrackingSystem | quality ("SR"/"SSR") | ExploreLogic |
| `evacuation_start` | EvacuationSystem | pointType | ExploreScreen, AudioMgr |
| `contract_unstable` | EvacuationSystem | unstableContracts | ContractQTEOverlay |
| `evacuation_result` | ContractQTEOverlay | success, lostContracts | ResultScreen |
| `suppress_result` | SuppressSystem | "success" / "fail" | CaptureOverlay |
| `ambush_triggered` | ExploreScreen | beast | 视觉反馈（"袭"字） |
| `beast_alerted` | ExploreScreen | beast | BeastRenderer（"!"符号） |
| `resource_changed` | SessionState | resType, amount | HUD |
| `screen_changed` | ScreenManager | newScreen, oldScreen | InputRouter |

### 3.2 ScreenManager.lua — 屏幕管理器

栈式管理，支持 `push`（模态叠层）和 `switch`（场景切换）。

```lua
local ScreenManager = {}
local stack = {}

function ScreenManager.switch(screenClass, params)
    for i = #stack, 1, -1 do
        if stack[i].onExit then stack[i]:onExit() end
        stack[i] = nil
    end
    stack = {}
    local screen = screenClass.new(params)
    table.insert(stack, screen)
    if screen.onEnter then screen:onEnter() end
    EventBus.emit("screen_changed", screen, nil)
end

function ScreenManager.push(screenClass, params)
    local current = stack[#stack]
    if current and current.onPause then current:onPause() end
    local screen = screenClass.new(params)
    table.insert(stack, screen)
    if screen.onEnter then screen:onEnter() end
end

function ScreenManager.pop()
    local top = stack[#stack]
    if top then
        if top.onExit then top:onExit() end
        table.remove(stack)
    end
    local current = stack[#stack]
    if current and current.onResume then current:onResume() end
end

function ScreenManager.current()
    return stack[#stack]
end

function ScreenManager.update(dt)
    local top = stack[#stack]
    if top and top.isModal then
        if top.update then top:update(dt) end
    else
        for _, s in ipairs(stack) do
            if s.update then s:update(dt) end
        end
    end
end

function ScreenManager.render(nvg, logW, logH, t)
    for _, s in ipairs(stack) do
        if s.render then s:render(nvg, logW, logH, t) end
    end
end

return ScreenManager
```

**Screen 生命周期接口**:

```lua
Screen.isModal = false   -- true 时底层暂停 update
function Screen:onEnter() end
function Screen:onExit() end
function Screen:onPause() end
function Screen:onResume() end
function Screen:update(dt) end
function Screen:render(nvg, logW, logH, t) end
function Screen:onInput(action, sx, sy) end
```

### 3.3 InputRouter.lua — 输入路由器

```lua
local InputRouter = {}
local hotZones = {}

function InputRouter.register(rect, callback, layer, owner)
    table.insert(hotZones, {
        rect = rect,        -- {x, y, w, h} 屏幕坐标
        callback = callback,
        layer = layer,
        owner = owner,
    })
end

function InputRouter.unregister(owner)
    for i = #hotZones, 1, -1 do
        if hotZones[i].owner == owner then
            table.remove(hotZones, i)
        end
    end
end

function InputRouter.dispatch(sx, sy, action)
    table.sort(hotZones, function(a, b) return a.layer > b.layer end)
    for _, zone in ipairs(hotZones) do
        local r = zone.rect
        if sx >= r.x and sx <= r.x + r.w and sy >= r.y and sy <= r.y + r.h then
            zone.callback(action, sx, sy)
            return true
        end
    end
    local screen = ScreenManager.current()
    if screen and screen.onInput then
        screen:onInput(action, sx, sy)
    end
    return false
end

InputRouter.touchStart = nil
InputRouter.touchStartTime = 0
InputRouter.CLICK_THRESHOLD = 0.15
InputRouter.DRAG_THRESHOLD = 8

return InputRouter
```

**输入层级**:

| Layer | 用途 | 坐标空间 |
|-------|------|---------|
| 100 | 模态叠层 | 屏幕（吞掉所有事件） |
| 50 | HUD 按钮 | 屏幕 |
| 20 | 虚拟摇杆 | 屏幕（底部左半区域） |
| 10 | 游戏世界交互 | 屏幕→世界转换 |

### 3.4 VirtualJoystick.lua — 虚拟摇杆

```lua
local VirtualJoystick = {}

VirtualJoystick.active = false
VirtualJoystick.cx = 0
VirtualJoystick.cy = 0
VirtualJoystick.dx = 0
VirtualJoystick.dy = 0
VirtualJoystick.radius = 50
VirtualJoystick.deadZone = 0.15

function VirtualJoystick.isInZone(sx, sy, logW, logH)
    return sx < logW * 0.50 and sy > logH * 0.83
end

function VirtualJoystick.onTouchDown(sx, sy, logW, logH)
    if not VirtualJoystick.isInZone(sx, sy, logW, logH) then return false end
    VirtualJoystick.active = true
    VirtualJoystick.cx = sx
    VirtualJoystick.cy = sy
    VirtualJoystick.dx = 0
    VirtualJoystick.dy = 0
    return true
end

function VirtualJoystick.onTouchMove(sx, sy)
    if not VirtualJoystick.active then return end
    local ox = sx - VirtualJoystick.cx
    local oy = sy - VirtualJoystick.cy
    local dist = math.sqrt(ox * ox + oy * oy)
    local maxDist = VirtualJoystick.radius
    if dist > maxDist then
        ox = ox / dist * maxDist
        oy = oy / dist * maxDist
        dist = maxDist
    end
    local norm = dist / maxDist
    if norm < VirtualJoystick.deadZone then
        VirtualJoystick.dx = 0
        VirtualJoystick.dy = 0
    else
        VirtualJoystick.dx = ox / maxDist
        VirtualJoystick.dy = oy / maxDist
    end
end

function VirtualJoystick.onTouchUp()
    VirtualJoystick.active = false
    VirtualJoystick.dx = 0
    VirtualJoystick.dy = 0
end

function VirtualJoystick.getMoveDirection()
    return VirtualJoystick.dx, -VirtualJoystick.dy  -- 屏幕 Y-down → 世界 Y-up
end

-- draw() 见 ui.md 视觉规格
return VirtualJoystick
```

---

## 四、碰撞系统

带角落滑动的分轴碰撞，防止玩家卡墙。

```lua
local CollisionSystem = {}

function CollisionSystem.tryMove(entity, dx, dy, map)
    local newX = entity.x + dx
    local newY = entity.y + dy
    local halfW = entity.halfW or 0.35
    local halfH = entity.halfH or 0.35

    if not CollisionSystem.blocked(newX, newY, halfW, halfH, map) then
        entity.x = newX
        entity.y = newY
        return
    end

    if not CollisionSystem.blocked(entity.x + dx, entity.y, halfW, halfH, map) then
        entity.x = entity.x + dx
        return
    end

    if not CollisionSystem.blocked(entity.x, entity.y + dy, halfW, halfH, map) then
        entity.y = entity.y + dy
        return
    end

    local nudge = 0.3
    if dx ~= 0 then
        for _, n in ipairs({nudge, -nudge}) do
            if not CollisionSystem.blocked(entity.x + dx, entity.y + n * math.abs(dx), halfW, halfH, map) then
                entity.x = entity.x + dx
                entity.y = entity.y + n * math.abs(dx)
                return
            end
        end
    end
end

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
```

---

## 五、战争迷雾系统

### 5.1 迷雾状态

每个瓦片三种可见性状态:

| 状态 | 含义 | 实体可见 | 可交互 |
|------|------|---------|--------|
| `DARK` (0) | 未探索 | 不可见 | 不可交互 |
| `EXPLORED` (1) | 走过但不在视野 | 不显示异兽/资源/线索 | 不可交互 |
| `VISIBLE` (2) | 当前视野内 | 全部可见 | 可交互 |

### 5.2 FogOfWar.lua

```lua
local FogOfWar = {}

FogOfWar.DARK     = 0
FogOfWar.EXPLORED = 1
FogOfWar.VISIBLE  = 2

FogOfWar.VISION_RADIUS = 4.5
FogOfWar.grid = nil
FogOfWar.width = 0
FogOfWar.height = 0

function FogOfWar.init(mapWidth, mapHeight)
    FogOfWar.width = mapWidth
    FogOfWar.height = mapHeight
    FogOfWar.grid = {}
    for y = 1, mapHeight do
        FogOfWar.grid[y] = {}
        for x = 1, mapWidth do
            FogOfWar.grid[y][x] = FogOfWar.DARK
        end
    end
end

function FogOfWar.update(playerX, playerY)
    for y = 1, FogOfWar.height do
        for x = 1, FogOfWar.width do
            if FogOfWar.grid[y][x] == FogOfWar.VISIBLE then
                FogOfWar.grid[y][x] = FogOfWar.EXPLORED
            end
        end
    end
    local r = FogOfWar.VISION_RADIUS
    local cx = math.floor(playerX) + 1
    local cy = math.floor(playerY) + 1
    local ri = math.ceil(r)
    for dy = -ri, ri do
        for dx = -ri, ri do
            local gx = cx + dx
            local gy = cy + dy
            if gx >= 1 and gx <= FogOfWar.width
               and gy >= 1 and gy <= FogOfWar.height then
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist <= r then
                    FogOfWar.grid[gy][gx] = FogOfWar.VISIBLE
                end
            end
        end
    end
end

function FogOfWar.getState(gx, gy)
    local x = gx + 1
    local y = gy + 1
    if x < 1 or x > FogOfWar.width or y < 1 or y > FogOfWar.height then
        return FogOfWar.DARK
    end
    return FogOfWar.grid[y][x]
end

function FogOfWar.collapseEdge(progress)
    local border = math.floor(progress * math.min(FogOfWar.width, FogOfWar.height) * 0.4)
    for y = 1, FogOfWar.height do
        for x = 1, FogOfWar.width do
            if x <= border or x > FogOfWar.width - border
               or y <= border or y > FogOfWar.height - border then
                FogOfWar.grid[y][x] = FogOfWar.DARK
            end
        end
    end
end

function FogOfWar.isEntityVisible(wx, wy)
    return FogOfWar.getState(math.floor(wx), math.floor(wy)) == FogOfWar.VISIBLE
end

return FogOfWar
```

### 5.3 灾变联动

灾变阶段推进时通过 `collapseEdge` 吞噬边缘:

| 灾变阶段 | 吞噬深度 |
|---------|---------|
| calm | 0 格 |
| warning | 边缘 1-2 格 → DARK |
| danger | 边缘 3-5 格 → DARK |
| collapse | 边缘 6-8 格 → DARK |

---

## 六、灾变计时器

```lua
local Timer = {}

Timer.duration = 480     -- 8 分钟
Timer.elapsed = 0
Timer.phase = "calm"

local PHASES = {
    { name = "calm",     start = 0,   endt = 240 },
    { name = "warning",  start = 240, endt = 330 },
    { name = "danger",   start = 330, endt = 420 },
    { name = "collapse", start = 420, endt = 480 },
}

function Timer.reset(duration)
    Timer.duration = duration or 480
    Timer.elapsed = 0
    Timer.phase = "calm"
end

function Timer.update(dt)
    Timer.elapsed = Timer.elapsed + dt
    local newPhase = "calm"
    for _, p in ipairs(PHASES) do
        if Timer.elapsed >= p.start and Timer.elapsed < p.endt then
            newPhase = p.name
            break
        end
    end
    if Timer.elapsed >= Timer.duration then
        newPhase = "collapsed"
    end
    if newPhase ~= Timer.phase then
        Timer.phase = newPhase
        EventBus.emit("phase_changed", Timer.phase, Timer.getRemaining())
    end
end

function Timer.getRemaining()
    return math.max(0, Timer.duration - Timer.elapsed)
end

function Timer.getPhase()
    return Timer.phase
end

return Timer
```

---

## 七、追踪系统

> 核心原则: 发现方式决定品质，不存在遭遇后的品质 roll。
> R = 自然游荡 | 3 线索 = SR | 5 线索 + 闪光判定 = SSR

```lua
local TrackingSystem = {}

TrackingSystem.CLUE_TYPES = {
    footprint  = { investigate_time = 2.0 },
    resonance  = { investigate_time = 2.0 },
    nest       = { investigate_time = 2.0 },
}
TrackingSystem.FAST_INVESTIGATE_TIME = 0.5  -- 有追迹灰时

TrackingSystem.clueCount = 0
TrackingSystem.clues = {}
TrackingSystem.srTriggered = false
TrackingSystem.ssrTriggered = false

function TrackingSystem.reset()
    TrackingSystem.clueCount = 0
    TrackingSystem.clues = {}
    TrackingSystem.srTriggered = false
    TrackingSystem.ssrTriggered = false
end

function TrackingSystem.getInvestigateTime(clueType, hasTraceAsh)
    if hasTraceAsh then return TrackingSystem.FAST_INVESTIGATE_TIME end
    local ct = TrackingSystem.CLUE_TYPES[clueType]
    return ct and ct.investigate_time or 2.0
end

function TrackingSystem.investigate(clue, hasTraceAsh)
    TrackingSystem.clueCount = TrackingSystem.clueCount + 1
    clue.investigated = true
    if hasTraceAsh then
        EventBus.emit("resource_changed", "traceAsh", -1)
    end
    EventBus.emit("clue_collected", clue.type, TrackingSystem.clueCount)

    if TrackingSystem.clueCount >= 3 and not TrackingSystem.srTriggered then
        TrackingSystem.srTriggered = true
        EventBus.emit("beast_spawn_request", "SR")
    end

    if TrackingSystem.clueCount >= 5 and not TrackingSystem.ssrTriggered then
        TrackingSystem.ssrTriggered = true
        if TrackingSystem.rollFlash() then
            EventBus.emit("beast_spawn_request", "SSR")
        else
            EventBus.emit("beast_spawn_request", "SR")
        end
    end
end

-- 闪光判定: 基础15% + 每多1线索(超5)+5% + 天命盘+15% + 保底加成
function TrackingSystem.rollFlash(hasTianmingpan)
    local base = 0.15
    local extraClues = math.max(0, TrackingSystem.clueCount - 5)
    local clueBonus = extraClues * 0.05
    local sealerBonus = hasTianmingpan and 0.15 or 0
    local pityBonus = PitySystem.getSSRFlashBonus()
    local totalChance = base + clueBonus + sealerBonus + pityBonus
    return math.random() < totalChance
end

return TrackingSystem
```

---

## 八、异兽 AI 状态机

### 8.1 FSM + 朝向系统

每只异兽有 `facing` 弧度角，决定视野方向。玩家从背后接触可触发偷袭加成。

```lua
local BeastAI = {}

BeastAI.STATE = {
    IDLE = "idle", WANDER = "wander", ALERT = "alert",
    FLEE = "flee", HIDDEN = "hidden",
}

BeastAI.SENSE_RANGE = { R = 3, SR = 4, SSR = 6 }

function BeastAI.update(beast, dt, playerX, playerY, map)
    local state = beast.aiState

    if state == "idle" then
        beast.idleTimer = (beast.idleTimer or 0) + dt
        if beast.idleTimer > beast.idleDuration then
            beast.aiState = "wander"
            beast.idleTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        end

    elseif state == "wander" then
        local arrived = BeastAI.moveToward(beast, beast.wanderTarget, dt, 1.5)
        if arrived then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 3
        end
        local dist = BeastAI.distTo(beast, playerX, playerY)
        local senseRange = BeastAI.SENSE_RANGE[beast.quality] or 3
        if dist < senseRange then
            local contactAngle = BeastAI.getContactType(beast, playerX, playerY)
            if contactAngle == "front" then
                if beast.quality == "SSR" then
                    beast.aiState = "flee"
                    beast.facing = math.atan2(beast.y - playerY, beast.x - playerX)
                else
                    beast.aiState = "alert"
                    beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
                end
            elseif contactAngle == "side" and beast.quality == "SSR" then
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
        beast.x = beast.x + math.cos(angle) * speed * dt
        beast.y = beast.y + math.sin(angle) * speed * dt
        CollisionSystem.tryMove(beast, 0, 0, map)
        if BeastAI.distTo(beast, playerX, playerY) > 8 then
            beast.aiState = "alert"
            beast.alertTimer = 0
        end

    elseif state == "hidden" then
        -- 等待追踪系统触发
    end
end

function BeastAI.moveToward(beast, target, dt, speed)
    if not target then return true end
    local dx = target.x - beast.x
    local dy = target.y - beast.y
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 0.1 then return true end
    beast.facing = math.atan2(dy, dx)
    local step = math.min(speed * dt, dist)
    beast.x = beast.x + (dx / dist) * step
    beast.y = beast.y + (dy / dist) * step
    return false
end

function BeastAI.distTo(beast, px, py)
    local dx = beast.x - px
    local dy = beast.y - py
    return math.sqrt(dx*dx + dy*dy)
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

return BeastAI
```

### 8.2 偷袭系统

```lua
function BeastAI.getContactType(beast, playerX, playerY)
    local toPlayerAngle = math.atan2(playerY - beast.y, playerX - beast.x)
    local diff = toPlayerAngle - (beast.facing or 0)
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
```

**ExploreScreen 调用侧**:

```lua
function ExploreScreen:onBeastContact(beast, playerX, playerY)
    local contactType = BeastAI.getContactType(beast, playerX, playerY)

    if contactType == "back" then
        beast.ambushBonus = true
        EventBus.emit("ambush_triggered", beast)
    elseif contactType == "front" then
        if math.random() < 0.50 then
            beast.aiState = "flee"
            beast.facing = math.atan2(beast.y - playerY, beast.x - playerX)
            EventBus.emit("beast_alerted", beast)
            return
        end
    end
    beast.aiState = "suppress"
    ScreenManager.push(SuppressOverlay, { beast = beast })
end
```

**偷袭效果**:

| 接触类型 | 角度范围 | 捕获率 | 压制窗口 |
|---------|---------|-------|---------|
| 背后偷袭 | 异兽背面 ±60° | +20% | +30% |
| 侧面接触 | ±60°~120° | 无 | 无 |
| 正面接触 | ±120°~180° | 无（50%逃跑） | 无 |

---

## 九、压制系统（QTE）

两种模式: 时机点击（R/SR）和连续封印（SSR）。

```lua
local SuppressSystem = {}

SuppressSystem.MODE_TIMING = "timing"
SuppressSystem.MODE_RAPID  = "rapid"

SuppressSystem.state = {
    mode = "timing",
    pointer = 0, direction = 1, speed = 1.0,
    targetZone = { 0.4, 0.6 },
    hitCount = 0, requiredHits = 1,
    tapCount = 0, requiredTaps = 8,
    rapidTimer = 0, rapidDuration = 3.0,
    active = false,
}

function SuppressSystem.start(beast, hasMirrorSand)
    local s = SuppressSystem.state
    s.hitCount = 0
    s.tapCount = 0
    s.active = true
    s.pointer = 0
    s.direction = 1
    s.rapidTimer = 0

    if beast.quality == "SSR" then
        s.mode = SuppressSystem.MODE_RAPID
        s.requiredTaps = 8
        s.rapidDuration = 3.0
    elseif beast.quality == "SR" then
        s.mode = SuppressSystem.MODE_TIMING
        s.speed = 1.6
        s.requiredHits = 2
        s.targetZone = { 0.35, 0.65 }
    else
        s.mode = SuppressSystem.MODE_TIMING
        s.speed = 1.0
        s.requiredHits = 1
        s.targetZone = { 0.30, 0.70 }
    end

    if hasMirrorSand then
        if s.mode == SuppressSystem.MODE_TIMING then
            s.targetZone[1] = s.targetZone[1] - 0.05
            s.targetZone[2] = s.targetZone[2] + 0.05
        else
            s.requiredTaps = 6
        end
    end

    if beast.ambushBonus then
        if s.mode == SuppressSystem.MODE_TIMING then
            local expand = (s.targetZone[2] - s.targetZone[1]) * 0.30 * 0.5
            s.targetZone[1] = math.max(0.05, s.targetZone[1] - expand)
            s.targetZone[2] = math.min(0.95, s.targetZone[2] + expand)
        else
            s.requiredTaps = math.max(4, s.requiredTaps - 2)
            s.rapidDuration = s.rapidDuration + 0.5
        end
    end
end

function SuppressSystem.update(dt)
    local s = SuppressSystem.state
    if not s.active then return end

    if s.mode == SuppressSystem.MODE_TIMING then
        s.pointer = s.pointer + s.direction * s.speed * dt
        if s.pointer >= 1.0 then s.pointer = 1.0; s.direction = -1 end
        if s.pointer <= 0.0 then s.pointer = 0.0; s.direction = 1 end
    else
        s.rapidTimer = s.rapidTimer + dt
        if s.rapidTimer >= s.rapidDuration then
            s.active = false
            EventBus.emit("suppress_result", "fail")
        end
    end
end

function SuppressSystem.tap()
    local s = SuppressSystem.state
    if not s.active then return nil end

    if s.mode == SuppressSystem.MODE_TIMING then
        if s.pointer >= s.targetZone[1] and s.pointer <= s.targetZone[2] then
            s.hitCount = s.hitCount + 1
            if s.hitCount >= s.requiredHits then
                s.active = false
                return "success"
            end
            s.speed = s.speed * 1.15
            s.targetZone[1] = s.targetZone[1] + 0.02
            s.targetZone[2] = s.targetZone[2] - 0.02
            return "hit"
        else
            s.active = false
            return "fail"
        end
    else
        s.tapCount = s.tapCount + 1
        if s.tapCount >= s.requiredTaps then
            s.active = false
            return "success"
        end
        return "hit"
    end
end

function SuppressSystem.getRapidProgress()
    local s = SuppressSystem.state
    if s.mode ~= SuppressSystem.MODE_RAPID then return 0 end
    return s.tapCount / s.requiredTaps
end

function SuppressSystem.getRapidTimeRatio()
    local s = SuppressSystem.state
    if s.mode ~= SuppressSystem.MODE_RAPID then return 1 end
    return math.max(0, 1 - s.rapidTimer / s.rapidDuration)
end

return SuppressSystem
```

---

## 十、捕获系统

> 品质在异兽生成时已确定，CaptureSystem 不做品质 roll。

```lua
local CaptureSystem = {}

function CaptureSystem.selectBestSealer(inventory)
    local tiers = { "T4", "T3", "T2", "T1" }
    for _, tier in ipairs(tiers) do
        local key = "sealer_" .. tier:lower()
        if (inventory[key] or 0) > 0 then
            return tier, key
        end
    end
    if (inventory.sealer_free or 0) > 0 then
        return "T1", "sealer_free"
    end
    return nil, nil
end

function CaptureSystem.attemptCapture(beast, sealerTier, inventory, sealerKey)
    local baseRate = ({ T1 = 0.75, T2 = 0.85, T3 = 0.92, T4 = 0.98 })[sealerTier]
    if beast.ambushBonus then
        baseRate = math.min(1.0, baseRate + 0.20)
    end
    inventory[sealerKey] = inventory[sealerKey] - 1

    if math.random() < baseRate then
        local result = {
            type = beast.type,
            name = beast.name,
            quality = beast.quality,
            stable = false,
        }
        if beast.quality == "SSR" then
            PitySystem.resetSSR()
            PitySystem.resetSR()
        elseif beast.quality == "SR" then
            PitySystem.incrementSSR()
            PitySystem.resetSR()
        else
            PitySystem.incrementSSR()
            PitySystem.incrementSR()
        end
        EventBus.emit("beast_captured", result, beast.quality)
        return result
    else
        EventBus.emit("capture_failed", beast)
        return nil
    end
end

return CaptureSystem
```

---

## 十一、保底系统

> 计数单位: 捕获成功次数（跨局累计）。SSR 硬保底 80 次，SR 硬保底 15 次。

```lua
local PitySystem = {}

PitySystem.ssrCount = 0
PitySystem.srCount = 0

local SSR_FLASH_BONUS = {
    { threshold = 20, bonus = 0.10 },
    { threshold = 40, bonus = 0.20 },
    { threshold = 60, bonus = 0.35 },
    { threshold = 80, bonus = 1.00 },
}

function PitySystem.getSSRFlashBonus()
    if PitySystem.ssrCount >= 80 then return 1.0 end
    for i = #SSR_FLASH_BONUS, 1, -1 do
        if PitySystem.ssrCount >= SSR_FLASH_BONUS[i].threshold then
            return SSR_FLASH_BONUS[i].bonus
        end
    end
    return 0
end

function PitySystem.getSRCluesNeeded()
    if PitySystem.srCount >= 15 then return 0 end
    return 3
end

function PitySystem.isSRGuaranteed()
    return PitySystem.srCount >= 15
end

function PitySystem.incrementSSR() PitySystem.ssrCount = PitySystem.ssrCount + 1 end
function PitySystem.incrementSR()  PitySystem.srCount = PitySystem.srCount + 1 end
function PitySystem.resetSSR()     PitySystem.ssrCount = 0 end
function PitySystem.resetSR()      PitySystem.srCount = 0 end

function PitySystem.save()
    SaveGuard.save("saves/pity.json", {
        ssr = PitySystem.ssrCount,
        sr = PitySystem.srCount,
    }, Config.DEVICE_ID)
end

function PitySystem.load()
    local data = SaveGuard.load("saves/pity.json", Config.DEVICE_ID)
    if data then
        PitySystem.ssrCount = data.ssr or 0
        PitySystem.srCount = data.sr or 0
    end
end

return PitySystem
```

---

## 十二、撤离系统

```lua
local EvacuationSystem = {}

EvacuationSystem.fixedPoints = {}
EvacuationSystem.evacuating = false
EvacuationSystem.evacuateTimer = 0
EvacuationSystem.evacuateDuration = 3
EvacuationSystem.currentPoint = nil

function EvacuationSystem.init(mapData)
    EvacuationSystem.fixedPoints = mapData.evacuationPoints or {}
end

function EvacuationSystem.getNearestPoint(playerX, playerY)
    local best, bestDist = nil, math.huge
    for _, pt in ipairs(EvacuationSystem.fixedPoints) do
        local dx = pt.x - playerX
        local dy = pt.y - playerY
        local d = math.sqrt(dx*dx + dy*dy)
        if d < bestDist then best = pt; bestDist = d end
    end
    return best, bestDist
end

function EvacuationSystem.startEvacuation(point)
    EvacuationSystem.evacuating = true
    EvacuationSystem.evacuateTimer = 0
    EvacuationSystem.currentPoint = point
    EvacuationSystem.evacuateDuration = point.duration or 3
    EventBus.emit("evacuation_start", point.type)
end

function EvacuationSystem.update(dt, playerX, playerY)
    if not EvacuationSystem.evacuating then return end
    local pt = EvacuationSystem.currentPoint
    local dx = pt.x - playerX
    local dy = pt.y - playerY
    if math.sqrt(dx*dx + dy*dy) > 1.5 then
        EvacuationSystem.cancel()
        return
    end
    EvacuationSystem.evacuateTimer = EvacuationSystem.evacuateTimer + dt
    if EvacuationSystem.evacuateTimer >= EvacuationSystem.evacuateDuration then
        EvacuationSystem.complete()
    end
end

function EvacuationSystem.complete()
    EvacuationSystem.evacuating = false
    local contracts = SessionState.getContracts()
    local soulCharms = SessionState.getItemCount("soul_charm")
    local unstableContracts = {}

    for _, contract in ipairs(contracts) do
        local triggerChance = ({ R = 0.05, SR = 0.30, SSR = 0.50 })[contract.quality]
        if soulCharms > 0 then
            local reduction = ({ R = 0.05, SR = 0.20, SSR = 0.30 })[contract.quality]
            triggerChance = math.max(0, triggerChance - reduction)
        end
        if math.random() < triggerChance then
            table.insert(unstableContracts, contract)
        end
    end

    if #unstableContracts > 0 then
        EventBus.emit("contract_unstable", unstableContracts)
    else
        EventBus.emit("evacuation_result", true, {})
    end
end

function EvacuationSystem.cancel()
    EvacuationSystem.evacuating = false
    EvacuationSystem.evacuateTimer = 0
end

return EvacuationSystem
```

### 灵契 QTE 逻辑

```lua
EvacuationSystem.contractQTE = {
    active = false,
    contracts = {},
    currentIdx = 0,
    warningTimer = 0,
    WARNING_DURATION = 1.0,
    pointer = 0,
    direction = 1,
    speed = 1.2,
    targetZone = { 0.25, 0.75 },
    lostContracts = {},
}

function EvacuationSystem.startContractQTE(contracts)
    local qte = EvacuationSystem.contractQTE
    qte.active = true
    qte.contracts = contracts
    qte.currentIdx = 1
    qte.lostContracts = {}
    qte.warningTimer = qte.WARNING_DURATION
    qte.pointer = 0
    qte.direction = 1
end

function EvacuationSystem.updateContractQTE(dt)
    local qte = EvacuationSystem.contractQTE
    if not qte.active then return end
    if qte.warningTimer > 0 then
        qte.warningTimer = qte.warningTimer - dt
        return
    end
    qte.pointer = qte.pointer + qte.direction * qte.speed * dt
    if qte.pointer >= 1.0 then qte.pointer = 1.0; qte.direction = -1 end
    if qte.pointer <= 0.0 then qte.pointer = 0.0; qte.direction = 1 end
end

function EvacuationSystem.tapContractQTE()
    local qte = EvacuationSystem.contractQTE
    if not qte.active or qte.warningTimer > 0 then return end

    local contract = qte.contracts[qte.currentIdx]
    if not (qte.pointer >= qte.targetZone[1] and qte.pointer <= qte.targetZone[2]) then
        table.insert(qte.lostContracts, contract)
    end

    qte.currentIdx = qte.currentIdx + 1
    if qte.currentIdx > #qte.contracts then
        qte.active = false
        EventBus.emit("evacuation_result", true, qte.lostContracts)
    else
        qte.warningTimer = qte.WARNING_DURATION
        qte.pointer = 0
        qte.direction = 1
    end
end
```

---

## 十三、合成系统

```lua
local CraftSystem = {}

CraftSystem.recipes = {
    { id = "sealer_t2", name = "青玉壶",  cost = { lingshi = 3 } },
    { id = "sealer_t3", name = "金缕珠",  cost = { lingshi = 5, shouhun = 1 } },
    { id = "sealer_t4", name = "天命盘",  cost = { lingshi = 15, shouhun = 5, tianjing = 2 } },
}

function CraftSystem.canCraft(recipeId, inventory)
    local recipe = CraftSystem.getRecipe(recipeId)
    if not recipe then return false end
    for res, amount in pairs(recipe.cost) do
        if (inventory[res] or 0) < amount then return false end
    end
    return true
end

function CraftSystem.craft(recipeId, inventory)
    if not CraftSystem.canCraft(recipeId, inventory) then return false end
    local recipe = CraftSystem.getRecipe(recipeId)
    for res, amount in pairs(recipe.cost) do
        inventory[res] = inventory[res] - amount
    end
    inventory[recipeId] = (inventory[recipeId] or 0) + 1
    EventBus.emit("resource_changed", "craft", recipeId)
    return true
end

function CraftSystem.getRecipe(id)
    for _, r in ipairs(CraftSystem.recipes) do
        if r.id == id then return r end
    end
    return nil
end

return CraftSystem
```

---

## 十四、每日任务与登录奖励

```lua
local DailySystem = {}

DailySystem.tasks = {
    { id = "explore_2",  desc = "成功撤离2次",  target = 2,  reward = { lingshi = 20 } },
    { id = "capture_5",  desc = "捕获5只异兽",  target = 5,  reward = { shouhun = 3 } },
    { id = "capture_sr", desc = "获得1只异色",   target = 1,  reward = { traceAsh = 5 } },
    { id = "collect_20", desc = "收集20个灵石",  target = 20, reward = { soulCharm = 1 } },
}

DailySystem.progress = {}

function DailySystem.reset()
    DailySystem.progress = {}
    for _, task in ipairs(DailySystem.tasks) do
        DailySystem.progress[task.id] = 0
    end
end

function DailySystem.increment(taskId, amount)
    amount = amount or 1
    DailySystem.progress[taskId] = (DailySystem.progress[taskId] or 0) + amount
end

function DailySystem.isComplete(taskId)
    local task = DailySystem.getTask(taskId)
    return task and (DailySystem.progress[taskId] or 0) >= task.target
end

function DailySystem.allComplete()
    for _, task in ipairs(DailySystem.tasks) do
        if not DailySystem.isComplete(task.id) then return false end
    end
    return true
end

function DailySystem.getTask(id)
    for _, t in ipairs(DailySystem.tasks) do
        if t.id == id then return t end
    end
end

DailySystem.loginRewards = {
    [1] = { lingshi = 15 },
    [2] = { shouhun = 5 },
    [3] = { sealer_t3 = 1 },
    [4] = { lingshi = 20, soulCharm = 2 },
    [5] = { shouhun = 8 },
    [6] = { tianjing = 1 },
    [7] = { sealer_t4 = 1, tianjing = 2 },
}

function DailySystem.getLoginDay(totalDays)
    return ((totalDays - 1) % 7) + 1
end

return DailySystem
```

---

## 十五、新手引导状态机

```lua
local TutorialSystem = {}

TutorialSystem.step = 0
TutorialSystem.active = false

local STEPS = {
    { id = "welcome",     trigger = "enter_map",          message = "欢迎来到灵境" },
    { id = "collect",     trigger = "lingshi >= 5",       message = "灵石可以合成封灵器" },
    { id = "investigate", trigger = "clue_collected",     message = "发现了异兽的踪迹！" },
    { id = "first_beast", trigger = "beast_spawned",      message = "异兽出现了！接近它" },
    { id = "suppress",    trigger = "suppress_start",     message = "在目标区域点击！" },
    { id = "captured",    trigger = "beast_captured",     message = "需要撤离才能带走它" },
    { id = "evacuate",    trigger = "near_evac_point",    message = "前往传送阵等待撤离" },
    { id = "complete",    trigger = "evacuation_success", message = "异兽已入图鉴" },
}

function TutorialSystem.start()
    TutorialSystem.step = 1
    TutorialSystem.active = true
end

function TutorialSystem.checkTrigger(triggerType, data)
    if not TutorialSystem.active then return end
    if TutorialSystem.step > #STEPS then
        TutorialSystem.active = false
        return
    end
    local current = STEPS[TutorialSystem.step]
    if current.trigger == triggerType then
        EventBus.emit("tutorial_message", current.message)
        TutorialSystem.step = TutorialSystem.step + 1
    end
end

function TutorialSystem.isFirstRun()
    local data = SaveGuard.load("saves/main.json", Config.DEVICE_ID)
    return not data or not data.tutorialDone
end

return TutorialSystem
```

---

## 十六、存档系统

### 16.1 文件结构

```
saves/
├── main.json          # 仓库资源、图鉴、每日任务、登录记录
├── pity.json          # 保底计数器（HMAC 校验）
└── session.json       # 单局中间状态（结算后删除）
```

### 16.2 引擎约束

- `io` 库不可用，使用 `File(context, path, mode)` + `fileSystem`
- JSON 编解码使用 `cjson`
- 路径使用相对路径，引擎自动映射沙箱目录

### 16.3 SaveGuard.lua

```lua
local SaveGuard = {}
local SALT = "shanhai_xunguang_2026"

function SaveGuard.computeHMAC(data, deviceId)
    local key = deviceId .. SALT
    local hash = 0
    for i = 1, #data do
        hash = (hash * 31 + string.byte(data, i) + string.byte(key, (i % #key) + 1)) % 2147483647
    end
    return string.format("%010d", hash)
end

function SaveGuard.save(path, tbl, deviceId)
    local json = cjson.encode(tbl)
    local hmac = SaveGuard.computeHMAC(json, deviceId)
    local wrapped = cjson.encode({ data = tbl, hmac = hmac })
    local file = File(context, path, FILE_WRITE)
    file:WriteLine(wrapped)
    file:Close()
end

function SaveGuard.load(path, deviceId)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(context, path, FILE_READ)
    local raw = file:ReadLine()
    file:Close()
    local wrapped = cjson.decode(raw)
    local json = cjson.encode(wrapped.data)
    local expected = SaveGuard.computeHMAC(json, deviceId)
    if wrapped.hmac ~= expected then
        print("[SaveGuard] 校验失败: " .. path)
        return nil
    end
    return wrapped.data
end

return SaveGuard
```

### 16.4 Session 存档时机

| 触发点 | 说明 |
|--------|------|
| 捕获成功 | 灵契入包时立即存档 |
| 区域切换 | 进入新区域时存档 |
| 灾变阶段变化 | phase_changed 事件触发 |
| 应用切到后台 | onPause 事件 |
| 每 60 秒 | 兜底定时存档 |

启动时检测到 `session.json` 存在则提示恢复上次探索。

---

## 十七、地图生成

### 17.1 规格

- 尺寸: **20×30 格**（宽×高，竖屏纵深探索）
- 出生点: 底部中央安全区
- 区域: 安全区（边缘2格）→ 搜索区 → 稀有区 → 高危区（纵深方向）

### 17.2 预计算策略

地图生成时预计算所有瓦片随机装饰数据，避免渲染时调用 `math.randomseed`:

```lua
function ExploreMap:generate(width, height, seed)
    math.randomseed(seed)
    self.tiles = {}
    for y = 1, height do
        self.tiles[y] = {}
        for x = 1, width do
            local tile = self:generateTile(x, y)
            tile.seed = math.random(0, 999)
            if tile.type == "grass" then
                tile.grassStrokes = self:precomputeGrassStrokes(tile)
            elseif tile.type == "rock" then
                tile.cunCount = 4 + math.random(0, 3)
            end
            tile.fibers = self:precomputeFibers(tile)
            self.tiles[y][x] = tile
        end
    end
    self:generateCluePositions()
    self:generateEvacuationPoints()
    self:generateResourceNodes()
end

function ExploreMap:precomputeGrassStrokes(tile)
    local strokes = {}
    local count = 2 + tile.seed % 3
    for i = 1, count do
        table.insert(strokes, {
            x1 = (math.random() - 0.5) * 0.6,
            y1 = (math.random() - 0.5) * 0.6,
            cx = (math.random() - 0.5) * 0.4,
            cy = (math.random() - 0.5) * 0.4,
            x2 = (math.random() - 0.5) * 0.5,
            y2 = (math.random() - 0.5) * 0.8,
            alpha = 0.20 + math.random() * 0.15,
            width = 0.8 + math.random() * 0.6,
            phase = math.random() * math.pi * 2,
        })
    end
    return strokes
end

function ExploreMap:precomputeFibers(tile)
    local fibers = {}
    for i = 1, 2 do
        table.insert(fibers, {
            x1 = math.random() * 0.8 - 0.4,
            y1 = math.random() * 0.8 - 0.4,
            x2 = math.random() * 0.8 - 0.4,
            y2 = math.random() * 0.8 - 0.4,
        })
    end
    return fibers
end
```

### 17.3 视锥剔除

只渲染 Camera 视野内 ±1 格的瓦片:

```lua
function ExploreScreen:renderTiles(nvg, t)
    local startGX = math.floor(Camera.x - Camera.logW / Camera.ppu * 0.5) - 1
    local endGX   = math.ceil(Camera.x + Camera.logW / Camera.ppu * 0.5) + 1
    local startGY = math.floor(Camera.y - Camera.viewH * 0.5) - 1
    local endGY   = math.ceil(Camera.y + Camera.viewH * 0.5) + 1

    for gy = startGY, endGY do
        for gx = startGX, endGX do
            local tile = self.map:getTile(gx, gy)
            if tile then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    InkTileRenderer.drawTile(nvg, tile, sx, sy, Camera.ppu, t, fogState)
                end
            end
        end
    end
end
```

---

## 十八、性能预算与质量分级

### 18.1 Config.lua

```lua
local Config = {}

Config.QUALITY = 1            -- 0=低 / 1=中 / 2=高
Config.MAX_PARTICLES = 15
Config.TILE_DETAIL = true
Config.ATMOSPHERE = true
Config.INK_FIBERS = true
Config.DEVICE_ID = ""

Config.MAP_WIDTH = 20
Config.MAP_HEIGHT = 30
Config.VISION_RADIUS = 4.5
Config.PLAYER_SPEED = 5

local frameHistory = {}
local adjustCooldown = 0

function Config.autoAdjust(dt)
    adjustCooldown = adjustCooldown - dt
    table.insert(frameHistory, dt)
    if #frameHistory > 90 then table.remove(frameHistory, 1) end
    if #frameHistory < 45 or adjustCooldown > 0 then return end

    local avg = 0
    for _, d in ipairs(frameHistory) do avg = avg + d end
    avg = avg / #frameHistory

    if avg > 1/40 and Config.QUALITY > 0 then
        Config.QUALITY = Config.QUALITY - 1
        Config.MAX_PARTICLES = math.max(5, Config.MAX_PARTICLES - 5)
        adjustCooldown = 5
    elseif avg < 1/55 and Config.QUALITY < 2 then
        Config.QUALITY = Config.QUALITY + 1
        Config.MAX_PARTICLES = math.min(30, Config.MAX_PARTICLES + 5)
        adjustCooldown = 10
    end
end

Config.performanceLocked = false
function Config.lockPerformance() Config.performanceLocked = true end
function Config.unlockPerformance()
    Config.performanceLocked = false
    frameHistory = {}
end

return Config
```

### 18.2 性能消耗估算

| 效果 | 每帧绘制调用 | 策略 |
|------|------------|------|
| 宣纸底色 | 1次 | 始终开启 |
| 瓦片墨色晕染 | ~200次 | 始终开启 |
| 瓦片笔触细节 | ~400次 | QUALITY≥1 |
| 宣纸纤维 | ~100次 | QUALITY≥2 |
| 边缘留白渐变 | 4次 | 始终开启 |
| 云雾/光柱 | 5~8次 | QUALITY≥1/2 |
| 异兽水墨形状 | ~40次/只 | 始终开启 |
| 墨迹光环 | ~10次/只 | 始终开启 |
| SSR 墨迹粒子 | ~15次 | MAX_PARTICLES |
| 封印演出 | ~80次/帧 | 锁定性能 |
| SSR 揭示演出 | ~150次/帧 | 锁定性能 |

### 18.3 贴图缓存（可选增强）

```lua
local TextureCache = {}
local cache = {}
local accessTime = {}
local nvgCtx = nil
local MAX_CACHE = 32

function TextureCache.init(ctx) nvgCtx = ctx end

function TextureCache.load(path, flags)
    if cache[path] then
        accessTime[path] = os.clock and os.clock() or 0
        return cache[path]
    end
    if TextureCache.count() >= MAX_CACHE then
        TextureCache.evictOldest()
    end
    local img = nvgCreateImage(nvgCtx, path, flags or 0)
    if img and img > 0 then
        cache[path] = img
        accessTime[path] = os.clock and os.clock() or 0
        return img
    end
    return nil
end

function TextureCache.count()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

function TextureCache.evictOldest()
    local oldestPath, oldestTime = nil, math.huge
    for path, t in pairs(accessTime) do
        if t < oldestTime then oldestPath = path; oldestTime = t end
    end
    if oldestPath then
        nvgDeleteImage(nvgCtx, cache[oldestPath])
        cache[oldestPath] = nil
        accessTime[oldestPath] = nil
    end
end

function TextureCache.release()
    for _, img in pairs(cache) do nvgDeleteImage(nvgCtx, img) end
    cache = {}
    accessTime = {}
end

return TextureCache
```

---

## 十九、数据文件

### 19.1 InkPalette.lua

> 唯一色彩定义源。色值定义见 ui.md 色彩体系章节。

```lua
local InkPalette = {
    paper     = { r=0.96, g=0.93, b=0.87 },
    paperWarm = { r=0.94, g=0.90, b=0.82 },
    inkDark   = { r=0.08, g=0.06, b=0.05 },
    inkStrong = { r=0.18, g=0.15, b=0.13 },
    inkMedium = { r=0.35, g=0.32, b=0.28 },
    inkLight  = { r=0.55, g=0.52, b=0.47 },
    inkWash   = { r=0.78, g=0.75, b=0.70 },
    cinnabar  = { r=0.76, g=0.23, b=0.18 },
    gold      = { r=0.80, g=0.68, b=0.20 },
    jade      = { r=0.30, g=0.58, b=0.45 },
    indigo    = { r=0.22, g=0.30, b=0.48 },
    azure     = { r=0.35, g=0.55, b=0.72 },
    qualR     = { r=0.55, g=0.52, b=0.47 },
    qualSR    = { r=0.35, g=0.55, b=0.72 },
    qualSSR   = { r=0.80, g=0.68, b=0.20 },
    miasmaLight = { r=0.45, g=0.15, b=0.12 },
    miasmaDark  = { r=0.30, g=0.05, b=0.05 },
}
return InkPalette
```

### 19.2 BeastData.lua

```lua
local BeastData = {
    { id="001", name="玄狐", element="火", bodySize=0.42, baseSpeed=2.0, fleeChance=0.3, senseRange=3 },
    { id="002", name="噬天", element="暗", bodySize=0.55, baseSpeed=1.5, fleeChance=0.2, senseRange=4 },
    { id="003", name="雷翼", element="雷", bodySize=0.50, baseSpeed=2.5, fleeChance=0.4, senseRange=4 },
    { id="004", name="白泽", element="光", bodySize=0.48, baseSpeed=1.8, fleeChance=0.3, senseRange=5 },
    { id="005", name="石灵", element="土", bodySize=0.45, baseSpeed=1.2, fleeChance=0.1, senseRange=3 },
    { id="006", name="水蛟", element="水", bodySize=0.50, baseSpeed=2.2, fleeChance=0.4, senseRange=4 },
    { id="007", name="风鸣", element="风", bodySize=0.38, baseSpeed=3.0, fleeChance=0.5, senseRange=4 },
    { id="008", name="土偶", element="土", bodySize=0.52, baseSpeed=1.0, fleeChance=0.1, senseRange=3 },
    { id="009", name="冰蚕", element="冰", bodySize=0.35, baseSpeed=1.5, fleeChance=0.3, senseRange=3 },
    { id="010", name="墨鸦", element="火", bodySize=0.40, baseSpeed=2.8, fleeChance=0.5, senseRange=4 },
}

function BeastData.getById(id)
    for _, b in ipairs(BeastData) do
        if b.id == id then return b end
    end
end

function BeastData.getRandomForQuality(quality)
    local pool = {}
    for _, b in ipairs(BeastData) do table.insert(pool, b) end
    return pool[math.random(#pool)]
end

return BeastData
```

---

## 二十、完整文件结构

```
scripts/
├── main.lua                        # 入口 + 崩溃恢复
├── Config.lua                      # 全局配置 + 质量分级
├── GameState.lua                   # 状态管理 + 存档读写
├── data/
│   ├── BeastData.lua               # 异兽数据表（10只）
│   └── InkPalette.lua              # 水墨调色板
├── systems/
│   ├── EventBus.lua                # 事件总线
│   ├── ScreenManager.lua           # 屏幕生命周期管理
│   ├── Camera.lua                  # 唯一坐标转换
│   ├── Timer.lua                   # 灾变计时器
│   ├── CollisionSystem.lua         # 碰撞（角落滑动）
│   ├── InputRouter.lua             # 分层点击路由
│   ├── VirtualJoystick.lua         # 虚拟摇杆
│   ├── FogOfWar.lua                # 战争迷雾
│   ├── TrackingSystem.lua          # 追踪系统
│   ├── BeastAI.lua                 # 异兽 AI（FSM + 朝向）
│   ├── SuppressSystem.lua          # 压制 QTE
│   ├── CaptureSystem.lua           # 捕获判定
│   ├── PitySystem.lua              # 保底系统
│   ├── EvacuationSystem.lua        # 撤离 + 灵契 QTE
│   ├── SessionState.lua            # 单局状态持久化
│   ├── CraftSystem.lua             # 合成系统
│   ├── DailySystem.lua             # 每日任务 + 登录
│   ├── TutorialSystem.lua          # 新手引导
│   ├── SaveGuard.lua               # 存档 HMAC 校验
│   ├── TextureCache.lua            # NanoVG 贴图缓存（LRU）
│   ├── BrushStrokes.lua            # 水墨笔触工具库
│   ├── InkRenderer.lua             # 水墨世界渲染
│   ├── InkTileRenderer.lua         # 水墨瓦片渲染
│   ├── BeastRenderer.lua           # 异兽水墨绘制
│   └── ExploreMap.lua              # 地图生成
└── screens/
    ├── LobbyScreen.lua             # 大厅
    ├── BookScreen.lua              # 图鉴
    ├── PrepareScreen.lua           # 进场准备
    ├── ExploreScreen.lua           # 探索主界面
    ├── ResultScreen.lua            # 结算
    ├── CraftScreen.lua             # 合成
    ├── DailyScreen.lua             # 每日任务/登录
    ├── SuppressOverlay.lua         # 压制 QTE 叠层
    ├── CaptureOverlay.lua          # 捕获演出叠层
    └── ContractQTEOverlay.lua      # 灵契 QTE 叠层
```

---

## 二十一、技术路线探索记录

### 探索 1: StaticSprite2D 方案（已放弃）

- 创建 Scene + Octree + Camera(orthographic) + Viewport
- 所有 Sprite2D 资源均无法加载（CDN 路径不兼容）
- **结论: 不可用**

### 探索 2: NanoVG 方案（已采用）

- 引擎全部 2D 示例均使用 NanoVG
- 零外部资源依赖，矢量渲染自适应分辨率
- 成功验证 NanoVG 世界 + UI 库 HUD 混合架构

### 探索 3: UI.Tabs 组件问题

- `RenderTabHeader` 报 `table index is nil`
- **解决: 手动实现标签页，绕过 UI.Tabs**

---

*技术方案版本: 4.0 · 最后更新: 2026-04-07*
*变更: 去除所有视觉渲染代码（归属 ui.md），去除策划数值定义（归属 game Planning.md），*
*去除 MVP/完整版区分，统一为可执行的完整技术方案。*
*渲染代码（BrushStrokes/InkTileRenderer/InkRenderer/BeastRenderer 的 draw 函数）*
*详见 ui.md 视觉规格。*
