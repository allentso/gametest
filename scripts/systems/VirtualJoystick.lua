--- 虚拟摇杆 - 竖屏左下激活区
local InkPalette = require("data.InkPalette")

local VirtualJoystick = {}

VirtualJoystick.active = false
VirtualJoystick.cx = 0
VirtualJoystick.cy = 0
VirtualJoystick.dx = 0
VirtualJoystick.dy = 0
VirtualJoystick.radius = 50
VirtualJoystick.deadZone = 0.15

--- 判断是否在摇杆激活区域（地图区域：顶部10%~底部80%范围内任意位置）
function VirtualJoystick.isInZone(sx, sy, logW, logH)
    return sy > logH * 0.10 and sy < logH * 0.80
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

--- 获取移动方向（屏幕Y-down → 世界Y-up）
function VirtualJoystick.getMoveDirection()
    return VirtualJoystick.dx, -VirtualJoystick.dy
end

--- 绘制摇杆（水墨风格：墨晕底盘 + 贝塞尔不规则描边 + 墨点旋钮）
function VirtualJoystick.draw(vg, logW, logH)
    if not VirtualJoystick.active then return end
    local P = InkPalette
    local BrushStrokes = require("render.BrushStrokes")
    local cx, cy = VirtualJoystick.cx, VirtualJoystick.cy
    local r = VirtualJoystick.radius

    -- 底盘：墨晕径向渐变
    BrushStrokes.inkWash(vg, cx, cy, r * 0.1, r, P.inkWash, 0.18)

    -- 不规则描边环：用 8 个控制点 + 贝塞尔曲线生成有机形状
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    local POINTS = 8
    local baseR = r * 0.88
    nvgBeginPath(vg)
    for i = 1, POINTS do
        local angle = (i - 1) / POINTS * math.pi * 2
        local nextAngle = i / POINTS * math.pi * 2
        -- 每个点的半径有确定性波动（±15%）
        local rNoise = 1.0 + ((i * 37 + 11) % 30 - 15) / 100
        local rNext = 1.0 + (((i + 1) * 37 + 11) % 30 - 15) / 100
        local px = cx + math.cos(angle) * baseR * rNoise
        local py = cy + math.sin(angle) * baseR * rNoise
        local npx = cx + math.cos(nextAngle) * baseR * rNext
        local npy = cy + math.sin(nextAngle) * baseR * rNext
        -- 控制点偏离圆心方向
        local midAngle = (angle + nextAngle) * 0.5
        local cpDist = baseR * (1.05 + ((i * 53) % 20 - 10) / 100)
        local cpx = cx + math.cos(midAngle) * cpDist
        local cpy = cy + math.sin(midAngle) * cpDist
        if i == 1 then
            nvgMoveTo(vg, px, py)
        end
        nvgQuadTo(vg, cpx, cpy, npx, npy)
    end
    nvgClosePath(vg)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, 0.30))
    nvgStroke(vg)
    nvgRestore(vg)

    -- 摇杆头：墨晕 + 不规则墨点
    local knobX = cx + VirtualJoystick.dx * r
    local knobY = cy + VirtualJoystick.dy * r
    BrushStrokes.inkWash(vg, knobX, knobY, 3, 14, P.cinnabar, 0.30)
    BrushStrokes.inkDotStable(vg, knobX, knobY, 10, P.cinnabar, 0.50, 77)
    BrushStrokes.inkDotStable(vg, knobX, knobY, 3, P.inkStrong, 0.30, 33)
end

return VirtualJoystick
