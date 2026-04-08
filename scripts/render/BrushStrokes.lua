--- 水墨笔触工具库 - 所有线条/墨点/墨晕的基础绘制
local InkPalette = require("data.InkPalette")

local BrushStrokes = {}

--- 水墨笔触线 - 模拟毛笔粗细变化和飞白断笔
---@param vg userdata NanoVG 上下文
---@param x1 number 起点X
---@param y1 number 起点Y
---@param x2 number 终点X
---@param y2 number 终点Y
---@param width number 基准线宽
---@param color table InkPalette 色值
---@param alpha number 不透明度 (0.18-0.25 推荐)
---@param seed number 随机种子
function BrushStrokes.inkLine(vg, x1, y1, x2, y2, width, color, alpha, seed)
    seed = seed or 0
    alpha = alpha or 0.22
    width = width or 1.5

    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end

    local segments = math.max(3, math.floor(len / 4))

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)

    for seg = 1, segments do
        -- 飞白断笔：一定概率跳过某段
        local rng = ((seed * 7 + seg * 13) % 100) / 100
        if rng > 0.15 then -- 85% 概率画这一段
            local t0 = (seg - 1) / segments
            local t1 = seg / segments
            local sx = x1 + dx * t0
            local sy = y1 + dy * t0
            local ex = x1 + dx * t1
            local ey = y1 + dy * t1

            -- 粗细变化：起笔略粗，中段最粗，收笔渐细
            local tMid = (t0 + t1) * 0.5
            local thickFactor = 1.0 + 0.3 * math.sin(tMid * math.pi)
            -- 加入随机波动
            thickFactor = thickFactor + ((seed * 3 + seg * 17) % 30 - 15) / 100

            local segAlpha = alpha * (0.85 + rng * 0.3)

            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            -- 微微弯曲的笔迹
            local cx = (sx + ex) * 0.5 + ((seed * 5 + seg * 11) % 10 - 5) * 0.3
            local cy = (sy + ey) * 0.5 + ((seed * 7 + seg * 3) % 10 - 5) * 0.3
            nvgQuadTo(vg, cx, cy, ex, ey)
            nvgStrokeWidth(vg, width * thickFactor)
            nvgStrokeColor(vg, nvgRGBAf(color.r, color.g, color.b, segAlpha))
            nvgStroke(vg)
        end
    end

    nvgRestore(vg)
end

--- 不规则墨点
---@param vg userdata
---@param cx number 中心X
---@param cy number 中心Y
---@param radius number 半径
---@param color table InkPalette 色值
---@param alpha number 不透明度
function BrushStrokes.inkDot(vg, cx, cy, radius, color, alpha)
    alpha = alpha or 0.5
    radius = radius or 3

    nvgSave(vg)
    nvgBeginPath(vg)
    -- 用椭圆模拟不规则形状
    local rx = radius * (0.85 + math.random() * 0.3)
    local ry = radius * (0.85 + math.random() * 0.3)
    nvgEllipse(vg, cx, cy, rx, ry)
    nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, alpha))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 固定参数的墨点（不使用 math.random，适合每帧调用）
function BrushStrokes.inkDotStable(vg, cx, cy, radius, color, alpha, seed)
    alpha = alpha or 0.5
    radius = radius or 3
    seed = seed or 0

    nvgSave(vg)
    nvgBeginPath(vg)
    local rng = (seed * 7 % 30) / 100  -- 0~0.29
    local rx = radius * (0.85 + rng)
    local ry = radius * (0.85 + (seed * 13 % 30) / 100)
    nvgEllipse(vg, cx, cy, rx, ry)
    nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, alpha))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 墨晕 - 径向渐变模拟墨水扩散
---@param vg userdata
---@param cx number 中心X
---@param cy number 中心Y
---@param innerR number 内径
---@param outerR number 外径
---@param color table InkPalette 色值
---@param alpha number 中心不透明度
function BrushStrokes.inkWash(vg, cx, cy, innerR, outerR, color, alpha)
    alpha = alpha or 0.15

    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR)
    local paint = nvgRadialGradient(vg, cx, cy, innerR, outerR,
        nvgRGBAf(color.r, color.g, color.b, alpha),
        nvgRGBAf(color.r, color.g, color.b, 0))
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgRestore(vg)
end

--- 皴法纹理 - 6-8 笔短促线条模拟岩石质感
---@param vg userdata
---@param cx number 中心X
---@param cy number 中心Y
---@param size number 区域大小
---@param color table InkPalette 色值
---@param alpha number 不透明度 0.15-0.25
---@param seed number 随机种子
---@param cunCount number 笔触数量
function BrushStrokes.cunTexture(vg, cx, cy, size, color, alpha, seed, cunCount)
    alpha = alpha or 0.20
    seed = seed or 0
    cunCount = cunCount or (6 + seed % 3)

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)

    for i = 1, cunCount do
        local hash = (seed * 7 + i * 31) % 1000
        local angle = (hash / 1000) * math.pi * 2
        local dist = (hash % 100 + 20) / 250 * size
        local sx = cx + math.cos(angle) * dist
        local sy = cy + math.sin(angle) * dist
        local len = size * (0.15 + (hash % 50) / 200)
        local ex = sx + math.cos(angle + 0.8) * len
        local ey = sy + math.sin(angle + 0.8) * len
        local w = 0.8 + (hash % 30) / 30

        local segAlpha = alpha * (0.7 + (hash % 30) / 100)

        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, ex, ey)
        nvgStrokeWidth(vg, w)
        nvgStrokeColor(vg, nvgRGBAf(color.r, color.g, color.b, segAlpha))
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

--- 毛笔描边矩形（用于按钮/卡片边框）
function BrushStrokes.inkRect(vg, x, y, w, h, color, alpha, seed)
    seed = seed or 0
    -- 四条边分别画笔触线
    BrushStrokes.inkLine(vg, x, y, x + w, y, 1.2, color, alpha, seed)
    BrushStrokes.inkLine(vg, x + w, y, x + w, y + h, 1.2, color, alpha, seed + 1)
    BrushStrokes.inkLine(vg, x + w, y + h, x, y + h, 1.2, color, alpha, seed + 2)
    BrushStrokes.inkLine(vg, x, y + h, x, y, 1.2, color, alpha, seed + 3)
end

return BrushStrokes
