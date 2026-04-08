--- 山海异闻录：寻光 - 入口文件
--- 水墨风异兽捕获撤离游戏
--- 纯 NanoVG 程序化渲染，无位图资源

require "LuaScripts/Utilities/Sample"

-- 核心模块
local Camera = require("systems.Camera")
local ScreenManager = require("systems.ScreenManager")
local GameState = require("systems.GameState")
local InputRouter = require("systems.InputRouter")

------------------------------------------------------------
-- 全局变量
------------------------------------------------------------
---@type userdata
local vg = nil       -- NanoVG 上下文
local fontSans = -1   -- 主字体 handle

-- 分辨率（模式B: 系统逻辑分辨率）
local logW = 0
local logH = 0
local dpr = 1.0

-- 时间
local totalTime = 0

------------------------------------------------------------
-- 生命周期
------------------------------------------------------------

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- 创建 NanoVG 上下文
    vg = nvgCreate(1)
    if not vg then
        print("[ERROR] Failed to create NanoVG context")
        return
    end
    print("[山海异闻录] NanoVG context created")

    -- 创建字体（只执行一次）
    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontSans == -1 then
        print("[ERROR] Failed to load font: Fonts/MiSans-Regular.ttf")
    else
        print("[山海异闻录] Font loaded, id=" .. fontSans)
    end

    -- 分辨率初始化
    updateResolution()

    -- 初始化持久数据
    GameState.init()
    GameState.checkDailyLogin()

    -- 进入大厅屏幕
    local LobbyScreen = require("screens.LobbyScreen")
    ScreenManager.switch(LobbyScreen)

    -- 订阅事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    print("[山海异闻录] Game started!")
end

function Stop()
    -- 保存状态
    GameState.save()
    -- 清理 NanoVG
    if vg then
        nvgDelete(vg)
        vg = nil
        print("[山海异闻录] NanoVG context deleted")
    end
end

------------------------------------------------------------
-- 分辨率 (模式B: 系统逻辑分辨率)
------------------------------------------------------------

function updateResolution()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    logW = physW / dpr
    logH = physH / dpr
    Camera.resize(logW, logH)
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    updateResolution()
end

------------------------------------------------------------
-- 更新
------------------------------------------------------------

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    totalTime = totalTime + dt
    ScreenManager.update(dt)
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    nvgBeginFrame(vg, logW, logH, dpr)
    ScreenManager.render(vg, logW, logH, totalTime)
    nvgEndFrame(vg)
end

------------------------------------------------------------
-- 输入: 屏幕坐标转逻辑坐标
------------------------------------------------------------

local function physToLogical(px, py)
    return px / dpr, py / dpr
end

-- 触摸状态追踪
local touchActive = false

------------------------------------------------------------
-- 鼠标输入
------------------------------------------------------------

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local sx, sy = physToLogical(input.mousePosition.x, input.mousePosition.y)
    ScreenManager.onInput("down", sx, sy)
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local sx, sy = physToLogical(input.mousePosition.x, input.mousePosition.y)
    ScreenManager.onInput("up", sx, sy)
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    local sx, sy = physToLogical(input.mousePosition.x, input.mousePosition.y)
    ScreenManager.onInput("move", sx, sy)
end

------------------------------------------------------------
-- 触摸输入
------------------------------------------------------------

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local sx, sy = physToLogical(px, py)
    touchActive = true
    ScreenManager.onInput("down", sx, sy)
end

---@param eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    if not touchActive then return end
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local sx, sy = physToLogical(px, py)
    ScreenManager.onInput("move", sx, sy)
end

---@param eventType string
---@param eventData TouchEndEventData
function HandleTouchEnd(eventType, eventData)
    local px = eventData["X"]:GetInt()
    local py = eventData["Y"]:GetInt()
    local sx, sy = physToLogical(px, py)
    touchActive = false
    ScreenManager.onInput("up", sx, sy)
end
