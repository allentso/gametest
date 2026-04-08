--- 相机 - 唯一坐标转换 + 平滑跟随 + 视锥剔除
local Camera = {}

Camera.x = 0
Camera.y = 0
Camera.viewH = 10       -- 竖屏可见世界高度（格）
Camera.ppu = 0           -- 运行时计算: logH / viewH
Camera.logW = 0
Camera.logH = 0

function Camera.resize(logW, logH)
    Camera.logW = logW
    Camera.logH = logH
    Camera.ppu = logH / Camera.viewH
end

--- 世界坐标 → 屏幕坐标
function Camera.toScreen(wx, wy)
    local sx = (wx - Camera.x) * Camera.ppu + Camera.logW * 0.5
    local sy = Camera.logH * 0.5 - (wy - Camera.y) * Camera.ppu
    return sx, sy
end

--- 屏幕坐标 → 世界坐标
function Camera.toWorld(sx, sy)
    local wx = (sx - Camera.logW * 0.5) / Camera.ppu + Camera.x
    local wy = (Camera.logH * 0.5 - sy) / Camera.ppu + Camera.y
    return wx, wy
end

--- 平滑跟随目标
function Camera.follow(targetX, targetY, dt)
    local lerp = 1 - math.exp(-5.0 * dt)
    Camera.x = Camera.x + (targetX - Camera.x) * lerp
    Camera.y = Camera.y + (targetY - Camera.y) * lerp
end

--- 判定世界坐标是否在视野内
function Camera.inView(wx, wy, margin)
    margin = margin or 1
    local halfW = (Camera.logW / Camera.ppu) * 0.5 + margin
    local halfH = Camera.viewH * 0.5 + margin
    return math.abs(wx - Camera.x) < halfW and math.abs(wy - Camera.y) < halfH
end

--- 获取视野范围（用于视锥剔除）
function Camera.getViewBounds()
    local halfW = (Camera.logW / Camera.ppu) * 0.5
    local halfH = Camera.viewH * 0.5
    return {
        minX = math.floor(Camera.x - halfW) - 1,
        maxX = math.ceil(Camera.x + halfW) + 1,
        minY = math.floor(Camera.y - halfH) - 1,
        maxY = math.ceil(Camera.y + halfH) + 1,
    }
end

return Camera
