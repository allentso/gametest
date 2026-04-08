--- 水墨世界渲染 - 统一调度 Layer 1/3/4 层
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local Camera = require("systems.Camera")
local Config = require("Config")

local InkRenderer = {}

--------------------------------------------------------------
-- 贴图图标 (nvgCreateImage 句柄，initImages 中一次性加载)
--------------------------------------------------------------
local imgHandles = {}  -- { type_name = nvg_image_handle }
local imgLoaded = false

--- 图标贴图路径映射
local IMAGE_PATHS = {
    -- 资源
    lingshi    = "image/res_lingshi_20260408061124.png",
    tianjing   = "image/res_tianjing_20260408061205.png",
    shouhun    = "image/res_shouhun_20260408061145.png",
    traceAsh   = "image/res_traceash_20260408061115.png",
    mirrorSand = "image/res_mirrorsand_20260408061217.png",
    soulCharm  = "image/res_soulcharm_20260408061106.png",
    -- 线索
    footprint  = "image/clue_footprint_20260408061831.png",
    resonance  = "image/clue_resonance_20260408061922.png",
    nest       = "image/clue_nest_20260408061952.png",
    -- 撤离点
    evac       = "image/evac_point_20260408062028.png",
}

--- 加载所有贴图（仅调用一次）
function InkRenderer.initImages(nvg)
    if imgLoaded then return end
    for name, path in pairs(IMAGE_PATHS) do
        local handle = nvgCreateImage(nvg, path, 0)
        if handle and handle > 0 then
            imgHandles[name] = handle
            print("[InkRenderer] Loaded icon: " .. name .. " handle=" .. handle)
        else
            print("[InkRenderer] WARN: Failed to load icon: " .. path)
        end
    end
    imgLoaded = true
end

--- 通用：在 (cx, cy) 处绘制正方形贴图图标
--- @param vg userdata  NanoVG 上下文
--- @param handle integer  nvgCreateImage 返回的句柄
--- @param cx number  中心 x
--- @param cy number  中心 y
--- @param size number  图标半径（最终绘制边长 = size*2）
--- @param alpha number  透明度 0~1
--- @param angle number  旋转角度（弧度），0 不旋转
local function drawIcon(vg, handle, cx, cy, size, alpha, angle)
    if not handle or handle <= 0 then return end
    local s = size * 2  -- 边长
    local x = cx - size
    local y = cy - size
    local paint = nvgImagePattern(vg, x, y, s, s, angle or 0, handle, alpha or 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, s, s)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

--- Layer 1: 宣纸底 + 程序化纤维纹理
function InkRenderer.drawPaperBase(vg, logW, logH, t)
    -- 全屏宣纸底色
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    local p = InkPalette.paper
    nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 1.0))
    nvgFill(vg)

    -- 画质≥2时：程序化纤维纹理
    if Config.INK_FIBERS then
        InkRenderer.drawFibers(vg, logW, logH, t)
    end

    nvgRestore(vg)
end

--- 纤维纹理（细微线条模拟宣纸质感）
function InkRenderer.drawFibers(vg, logW, logH, t)
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local fiberColor = InkPalette.inkWash

    -- 固定位置的纤维线（基于屏幕分区，不用random）
    local stepX = logW / 8
    local stepY = logH / 12
    for i = 0, 7 do
        for j = 0, 11 do
            local hash = (i * 97 + j * 31) % 100
            if hash < 25 then  -- 25%概率画纤维
                local sx = i * stepX + (hash * 3 % stepX)
                local sy = j * stepY + (hash * 7 % stepY)
                local angle = (hash * 11 % 360) * math.pi / 180
                local len = 8 + hash % 12
                local ex = sx + math.cos(angle) * len
                local ey = sy + math.sin(angle) * len

                nvgBeginPath(vg)
                nvgMoveTo(vg, sx, sy)
                nvgLineTo(vg, ex, ey)
                nvgStrokeWidth(vg, 0.3 + (hash % 5) * 0.1)
                nvgStrokeColor(vg, nvgRGBAf(fiberColor.r, fiberColor.g, fiberColor.b, 0.06))
                nvgStroke(vg)
            end
        end
    end
    nvgRestore(vg)
end

--- 简易角度噪声（基于 sin 叠加，不依赖 Perlin）
local function angleNoise(angle, t, seed)
    local a = angle
    return math.sin(a * 3.0 + t * 0.8 + seed)      * 0.40
         + math.sin(a * 7.0 - t * 1.2 + seed * 2.3) * 0.30
         + math.sin(a * 13.0 + t * 0.5 + seed * 5.7) * 0.20
         + math.sin(a * 21.0 - t * 1.8 + seed * 0.7) * 0.10
end

--- Layer 3: 迷雾渲染 - 浓墨泼洒 + 不规则有机边缘
function InkRenderer.drawFog(vg, logW, logH, playerSX, playerSY, visionPx, t, disasterProgress)
    nvgSave(vg)

    local inkD = InkPalette.inkDark
    local fogAlpha = 0.96

    ---------------------------------------------------
    -- Step 1: 核心径向遮罩（收窄过渡带 → 更锐利的明暗交界）
    ---------------------------------------------------
    local innerR = visionPx * 0.70
    local outerR = visionPx * 1.05

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    local basePaint = nvgRadialGradient(vg, playerSX, playerSY, innerR, outerR,
        nvgRGBAf(0, 0, 0, 0),
        nvgRGBAf(inkD.r, inkD.g, inkD.b, fogAlpha))
    nvgFillPaint(vg, basePaint)
    nvgFill(vg)

    ---------------------------------------------------
    -- Step 2: 浓墨泼溅墨团（大尺寸、高 alpha、不规则分布）
    ---------------------------------------------------
    local BLOB_COUNT = Config.QUALITY >= 1 and 14 or 8
    for i = 1, BLOB_COUNT do
        local baseAngle = (i / BLOB_COUNT) * math.pi * 2
        local noise = angleNoise(baseAngle, t, 42)
        local blobDist = visionPx * (0.85 + noise * 0.20)
        local bx = playerSX + math.cos(baseAngle) * blobDist
        local by = playerSY + math.sin(baseAngle) * blobDist
        local blobR = visionPx * (0.15 + math.abs(noise) * 0.12)
        local blobAlpha = 0.40 + math.abs(noise) * 0.25
        BrushStrokes.inkWash(vg, bx, by, blobR * 0.10, blobR, inkD, blobAlpha)
    end

    ---------------------------------------------------
    -- Step 2.5: 外围大块泼墨飞溅（期望图中远处的深墨斑点）
    ---------------------------------------------------
    local OUTER_BLOB = Config.QUALITY >= 1 and 8 or 4
    for i = 1, OUTER_BLOB do
        local hash = (i * 97 + 31) % 1000
        local angle = (i / OUTER_BLOB) * math.pi * 2 + (hash % 100) / 100
        local dist = visionPx * (1.3 + (hash % 300) / 600)
        local bx = playerSX + math.cos(angle) * dist
        local by = playerSY + math.sin(angle) * dist
        if bx > -50 and bx < logW + 50 and by > -50 and by < logH + 50 then
            local blobR = visionPx * (0.08 + (hash % 80) / 500)
            BrushStrokes.inkWash(vg, bx, by, blobR * 0.15, blobR, inkD, 0.55)
        end
    end

    ---------------------------------------------------
    -- Step 3: 散落墨点（加大尺寸和 alpha）
    ---------------------------------------------------
    local SPLAT_COUNT = Config.QUALITY >= 1 and 22 or 12
    for i = 1, SPLAT_COUNT do
        local hash = (i * 73 + 17) % 1000
        local angle = (i / SPLAT_COUNT) * math.pi * 2 + math.sin(t * 0.25 + i * 1.3) * 0.18
        local dotDist = visionPx * (0.65 + (hash % 500) / 1000)
        local dx = playerSX + math.cos(angle) * dotDist
        local dy = playerSY + math.sin(angle) * dotDist
        local dotSize = 4 + (hash % 100) / 8
        local pulse = math.sin(t * 0.8 + i * 1.1) * 0.5 + 0.5
        local dotAlpha = 0.20 + pulse * 0.25
        BrushStrokes.inkDotStable(vg, dx, dy, dotSize, inkD, dotAlpha, hash)
    end

    ---------------------------------------------------
    -- Step 4: 细墨尘微粒
    ---------------------------------------------------
    if Config.QUALITY >= 1 then
        for i = 1, 16 do
            local hash = (i * 137 + 53) % 1000
            local angle = (hash / 1000) * math.pi * 2 + math.sin(t * 0.3 + i * 1.7) * 0.2
            local dustR = visionPx * (0.75 + (hash % 350) / 1000)
            local dx = playerSX + math.cos(angle) * dustR
            local dy = playerSY + math.sin(angle) * dustR
            local pulse = math.sin(t * 1.2 + i * 0.9) * 0.5 + 0.5
            local dustAlpha = 0.12 + pulse * 0.18
            local dustSize = 1.5 + (hash % 25) / 10
            nvgBeginPath(vg)
            nvgCircle(vg, dx, dy, dustSize)
            nvgFillColor(vg, nvgRGBAf(inkD.r, inkD.g, inkD.b, dustAlpha))
            nvgFill(vg)
        end
    end

    ---------------------------------------------------
    -- 灾变瘴气暗角
    ---------------------------------------------------
    if disasterProgress and disasterProgress > 0 then
        local miasmaAlpha = disasterProgress * 0.5
        local mc = InkPalette.miasmaDark
        local cornerR = logW * 0.6 * (1 - disasterProgress * 0.3)
        for _, corner in ipairs({
            {0, 0}, {logW, 0}, {0, logH}, {logW, logH}
        }) do
            BrushStrokes.inkWash(vg, corner[1], corner[2],
                cornerR * 0.2, cornerR,
                mc, miasmaAlpha)
        end
        if disasterProgress > 0.5 then
            local pulse = math.sin(t * 3) * 0.05 + 0.12
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, logW, logH)
            nvgFillColor(vg, nvgRGBAf(mc.r, mc.g, mc.b, pulse * (disasterProgress - 0.5) * 2))
            nvgFill(vg)
        end
    end

    nvgRestore(vg)
end

--- Layer 4.1: 云雾氛围（世界坐标系漂浮墨云 + 屏幕边缘渐隐）
function InkRenderer.drawAtmosphere(vg, logW, logH, t)
    if not Config.ATMOSPHERE then return end

    nvgSave(vg)
    local wash = InkPalette.inkWash

    -- 屏幕边缘渐隐（保留原有效果，略微增强）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH * 0.06)
    local topPaint = nvgLinearGradient(vg, 0, 0, 0, logH * 0.06,
        nvgRGBAf(wash.r, wash.g, wash.b, 0.14),
        nvgRGBAf(wash.r, wash.g, wash.b, 0))
    nvgFillPaint(vg, topPaint)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, 0, logH * 0.94, logW, logH * 0.06)
    local botPaint = nvgLinearGradient(vg, 0, logH * 0.94, 0, logH,
        nvgRGBAf(wash.r, wash.g, wash.b, 0),
        nvgRGBAf(wash.r, wash.g, wash.b, 0.10))
    nvgFillPaint(vg, botPaint)
    nvgFill(vg)

    -- 世界坐标系漂浮墨云：3~5 团淡墨晕随世界位置缓慢漂移
    local camX = Camera.x or 0
    local camY = Camera.y or 0
    local ppu = Camera.ppu or 40
    local CLOUD_COUNT = 4
    for i = 1, CLOUD_COUNT do
        local seed = i * 137
        -- 世界坐标中的固定锚点（大范围散布）
        local worldAnchorX = ((seed * 7) % 40) - 20
        local worldAnchorY = ((seed * 13) % 60) - 30
        -- 缓慢漂移
        worldAnchorX = worldAnchorX + math.sin(t * 0.15 + i * 2.1) * 2.0
        worldAnchorY = worldAnchorY + math.cos(t * 0.12 + i * 1.7) * 1.5
        -- 转为屏幕坐标
        local screenX, screenY = Camera.toScreen(worldAnchorX, worldAnchorY)
        -- 只在屏幕附近才绘制
        if screenX > -200 and screenX < logW + 200
           and screenY > -200 and screenY < logH + 200 then
            local cloudR = ppu * (1.5 + (seed % 100) / 50)  -- 1.5~3.5 格大小
            local cloudAlpha = 0.04 + (seed % 40) / 1000  -- 0.04~0.079，非常淡
            -- 呼吸脉动
            cloudAlpha = cloudAlpha * (0.8 + math.sin(t * 0.4 + i * 1.3) * 0.2)
            BrushStrokes.inkWash(vg, screenX, screenY,
                cloudR * 0.1, cloudR, wash, cloudAlpha)
        end
    end

    nvgRestore(vg)
end

--- Layer 4.2: 边缘留白（水墨画卷的毛边效果）
function InkRenderer.drawEdgeWhitespace(vg, logW, logH)
    nvgSave(vg)
    local p = InkPalette.paper
    local edgeW = 4

    -- 上下左右边缘微微覆盖一层纸色
    for _, rect in ipairs({
        {0, 0, logW, edgeW},           -- 上
        {0, logH - edgeW, logW, edgeW}, -- 下
        {0, 0, edgeW, logH},           -- 左
        {logW - edgeW, 0, edgeW, logH}, -- 右
    }) do
        nvgBeginPath(vg)
        nvgRect(vg, rect[1], rect[2], rect[3], rect[4])
        nvgFillColor(vg, nvgRGBAf(p.r, p.g, p.b, 0.5))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

--- Toast 消息
function InkRenderer.drawToast(vg, cx, cy, message, alpha, screenW)
    if not message or alpha <= 0 then return end

    nvgSave(vg)
    local tw = math.min((screenW or 400) * 0.7, 280)
    local th = 36
    local tx = cx - tw * 0.5
    local ty = cy - th * 0.5

    -- 卷轴底
    local pw = InkPalette.paperWarm
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tx, ty, tw, th, 4)
    nvgFillColor(vg, nvgRGBAf(pw.r, pw.g, pw.b, 0.92 * alpha))
    nvgFill(vg)

    -- 双层墨框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tx + 1, ty + 1, tw - 2, th - 2, 3)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.60 * alpha))
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, tx + 3, ty + 3, tw - 6, th - 6, 2)
    nvgStrokeWidth(vg, 0.5)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
        0.40 * alpha))
    nvgStroke(vg)

    -- 卷轴两端圆柱
    for _, ex in ipairs({tx + 3, tx + tw - 3}) do
        nvgBeginPath(vg)
        nvgCircle(vg, ex, cy, 3)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.40 * alpha))
        nvgFill(vg)
    end

    -- 文字
    nvgFontSize(vg, 14)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.85 * alpha))
    nvgText(vg, cx, cy, message)
    nvgRestore(vg)
end

--- 绘制玩家角色（俯视斗笠）
function InkRenderer.drawPlayer(vg, sx, sy, ppu, facing, t)
    local r = ppu * 0.55
    local ink = InkPalette.inkStrong
    local cin = InkPalette.cinnabar

    nvgSave(vg)

    -- 行走烟尘（3个渐隐墨团在身后）
    if facing then
        local backX = -math.cos(-facing)
        local backY = -math.sin(-facing)
        for i = 1, 3 do
            local dist = r * (0.6 + i * 0.35)
            local dustAlpha = (0.18 - i * 0.04) * (math.sin(t * 3 + i) * 0.3 + 0.7)
            local dustR = r * (0.15 + i * 0.06)
            BrushStrokes.inkWash(vg,
                sx + backX * dist, sy + backY * dist,
                dustR * 0.3, dustR,
                InkPalette.inkWash, dustAlpha)
        end
    end

    -- 地面投影（椭圆形暗影）
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy + r * 0.35, r * 0.50, r * 0.18)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.25))
    nvgFill(vg)

    -- 斗笠主体（大浓墨圆 + 编织纹路）
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.50)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.75))
    nvgFill(vg)

    -- 斗笠编织线（2条十字线）
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.40, sy)
    nvgLineTo(vg, sx + r * 0.40, sy)
    nvgMoveTo(vg, sx, sy - r * 0.40)
    nvgLineTo(vg, sx, sy + r * 0.40)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.30))
    nvgStroke(vg)

    -- 斗笠帽檐描边（呼吸脉动）
    local breathe = 1.0 + math.sin(t * 2) * 0.03
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.55 * breathe)
    nvgStrokeWidth(vg, 1.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.60))
    nvgStroke(vg)

    -- 外层淡墨晕圈
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.70)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.25))
    nvgStroke(vg)

    -- 顶点笠尖（浓墨实点）
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.10)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.90))
    nvgFill(vg)

    -- 方向指示（朱砂箭头，加粗加长）
    if facing then
        local dirX = math.cos(-facing)
        local dirY = math.sin(-facing)
        local tipX = sx + dirX * r * 0.85
        local tipY = sy + dirY * r * 0.85
        local baseX = sx + dirX * r * 0.50
        local baseY = sy + dirY * r * 0.50
        nvgBeginPath(vg)
        nvgMoveTo(vg, baseX, baseY)
        nvgLineTo(vg, tipX, tipY)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.65))
        nvgStroke(vg)
        local perpX = -dirY * r * 0.12
        local perpY = dirX * r * 0.12
        nvgBeginPath(vg)
        nvgMoveTo(vg, tipX, tipY)
        nvgLineTo(vg, tipX - dirX * r * 0.15 + perpX, tipY - dirY * r * 0.15 + perpY)
        nvgMoveTo(vg, tipX, tipY)
        nvgLineTo(vg, tipX - dirX * r * 0.15 - perpX, tipY - dirY * r * 0.15 - perpY)
        nvgStrokeWidth(vg, 2.0)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.60))
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

--- 绘制线索 —— 三种类型各自独立视觉
function InkRenderer.drawClue(vg, clue, sx, sy, ppu, t)
    local r = ppu * 0.42
    local cin = InkPalette.cinnabar
    local ink = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium

    -- 底层朱砂脉冲光圈
    local pulseR = r * (1.2 + math.sin(t * 2.5) * 0.15)
    BrushStrokes.inkWash(vg, sx, sy, pulseR * 0.3, pulseR, cin, 0.12)

    -- 优先使用贴图
    local handle = imgHandles[clue.type]
    if handle then
        local bobY = math.sin(t * 1.8 + (clue.x or 0) * 2.1) * ppu * 0.025
        drawIcon(vg, handle, sx, sy + bobY, r, 0.90, 0)
        return
    end

    -- 矢量 fallback：三种线索各有独立形态
    nvgSave(vg)
    local bobY = math.sin(t * 1.8 + (clue.x or 0) * 2.1) * ppu * 0.025
    local cy = sy + bobY

    if clue.type == "footprint" then
        -- 足迹：两个前后排列的爪印（暖褐色）
        local pawC = { r = 0.45, g = 0.35, b = 0.25 }
        for step = -1, 1, 2 do
            local px = sx + step * r * 0.15
            local py = cy + step * r * 0.30
            -- 主掌垫
            nvgBeginPath(vg)
            nvgEllipse(vg, px, py, r * 0.16, r * 0.12)
            nvgFillColor(vg, nvgRGBAf(pawC.r, pawC.g, pawC.b, 0.65))
            nvgFill(vg)
            -- 三个趾垫
            for toe = -1, 1 do
                local tx = px + toe * r * 0.10
                local ty = py - r * 0.18
                nvgBeginPath(vg)
                nvgCircle(vg, tx, ty, r * 0.05)
                nvgFillColor(vg, nvgRGBAf(pawC.r, pawC.g, pawC.b, 0.55))
                nvgFill(vg)
            end
        end
        -- 淡淡的妖气弧线
        nvgBeginPath(vg)
        nvgArc(vg, sx, cy, r * 0.50, math.pi * 0.2, math.pi * 0.8, NVG_CW)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.25 + math.sin(t * 2) * 0.08))
        nvgStroke(vg)

    elseif clue.type == "resonance" then
        -- 共鸣：同心脉冲环 + 中心灵光点（石青色系）
        local az = InkPalette.azure
        for ring = 1, 3 do
            local rr = r * (0.20 + ring * 0.18)
            local ringPhase = (t * 1.5 + ring * 0.8) % (math.pi * 2)
            local ringAlpha = math.max(0, 0.35 - ring * 0.08) * (0.6 + math.sin(ringPhase) * 0.4)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, cy, rr)
            nvgStrokeWidth(vg, 1.8 - ring * 0.3)
            nvgStrokeColor(vg, nvgRGBAf(az.r, az.g, az.b, ringAlpha))
            nvgStroke(vg)
        end
        -- 中心灵光
        local coreAlpha = 0.50 + math.sin(t * 3) * 0.15
        nvgBeginPath(vg)
        nvgCircle(vg, sx, cy, r * 0.12)
        nvgFillColor(vg, nvgRGBAf(az.r, az.g, az.b, coreAlpha))
        nvgFill(vg)
        BrushStrokes.inkWash(vg, sx, cy, r * 0.05, r * 0.25, az, 0.20)

    elseif clue.type == "nest" then
        -- 巢穴：碗状弧线 + 内部碎屑 + 朱砂标记
        nvgLineCap(vg, NVG_ROUND)
        -- 巢碗弧线
        nvgBeginPath(vg)
        nvgArc(vg, sx, cy + r * 0.05, r * 0.35, math.pi * 0.15, math.pi * 0.85, NVG_CW)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
        nvgStroke(vg)
        -- 交织短线（巢的编织感）
        for i = 1, 4 do
            local hash = ((clue.x or 0) * 7 + i * 23) % 100
            local lx = sx + (hash % 20 - 10) * r * 0.02
            local ly1 = cy + r * 0.10 - (hash % 8) * r * 0.02
            local ly2 = cy + r * 0.30
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx - r * 0.08, ly1)
            nvgLineTo(vg, lx + r * 0.08, ly2)
            nvgStrokeWidth(vg, 1.2)
            nvgStrokeColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b, 0.35))
            nvgStroke(vg)
        end
        -- 巢中朱砂标记点
        BrushStrokes.inkDotStable(vg, sx, cy + r * 0.08, 3.5, cin, 0.45,
            (clue.x or 0) * 31 + 77)
    end

    nvgRestore(vg)
end

--- 绘制资源点 —— 六种资源各有独立矢量图标
function InkRenderer.drawResource(vg, res, sx, sy, ppu, t, playerDist)
    local r = ppu * 0.45
    local ink = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium

    -- 底部光晕颜色按类型区分
    local glowColor = InkPalette.inkWash
    local glowAlpha = 0.18
    if res.type == "lingshi" then
        glowColor = InkPalette.jade;   glowAlpha = 0.22
        if playerDist and playerDist < 3 then
            glowAlpha = 0.22 + (3 - playerDist) / 3 * 0.20
        end
    elseif res.type == "tianjing" then
        glowColor = InkPalette.gold;   glowAlpha = 0.25
    elseif res.type == "shouhun" then
        glowColor = InkPalette.indigo; glowAlpha = 0.22
    elseif res.type == "traceAsh" then
        glowColor = InkPalette.inkWash; glowAlpha = 0.16
    elseif res.type == "mirrorSand" then
        glowColor = InkPalette.azure;  glowAlpha = 0.20
    elseif res.type == "soulCharm" then
        glowColor = InkPalette.gold;   glowAlpha = 0.20
    end

    local pulse = math.sin(t * 2.0 + (res.x or 0) * 3.7) * 0.04
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 1.15, glowColor, glowAlpha + pulse)

    -- 优先使用贴图
    local handle = imgHandles[res.type]
    if handle then
        local bobY = math.sin(t * 1.5 + (res.y or 0) * 2.3) * ppu * 0.03
        drawIcon(vg, handle, sx, sy + bobY, r, 0.92, 0)
        return
    end

    -- 矢量 fallback：每种资源独立图标
    nvgSave(vg)
    local bobY = math.sin(t * 1.5 + (res.y or 0) * 2.3) * ppu * 0.03
    local cy = sy + bobY

    if res.type == "lingshi" then
        -- 灵石：六角翡翠结晶体
        local jade = InkPalette.jade
        local sides = 6
        nvgBeginPath(vg)
        for i = 0, sides do
            local a = (i / sides) * math.pi * 2 - math.pi / 2
            local pr = r * 0.38
            local px = sx + math.cos(a) * pr
            local py = cy + math.sin(a) * pr
            if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgFillColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.40))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.70))
        nvgStroke(vg)
        -- 内部光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, cy - r * 0.30)
        nvgLineTo(vg, sx - r * 0.10, cy + r * 0.15)
        nvgMoveTo(vg, sx, cy - r * 0.30)
        nvgLineTo(vg, sx + r * 0.12, cy + r * 0.10)
        nvgStrokeWidth(vg, 0.8)
        nvgStrokeColor(vg, nvgRGBAf(1, 1, 1, 0.35))
        nvgStroke(vg)
        -- 顶部高光
        local sparkle = 0.3 + math.sin(t * 2.5) * 0.15
        nvgBeginPath(vg)
        nvgCircle(vg, sx - r * 0.08, cy - r * 0.15, r * 0.06)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, sparkle))
        nvgFill(vg)

    elseif res.type == "tianjing" then
        -- 天晶：菱形钻石 + 金色辉光
        local gold = InkPalette.gold
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, cy - r * 0.42)
        nvgLineTo(vg, sx + r * 0.28, cy)
        nvgLineTo(vg, sx, cy + r * 0.42)
        nvgLineTo(vg, sx - r * 0.28, cy)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(gold.r, gold.g, gold.b, 0.35))
        nvgFill(vg)
        nvgStrokeWidth(vg, 2.0)
        nvgStrokeColor(vg, nvgRGBAf(gold.r, gold.g, gold.b, 0.75))
        nvgStroke(vg)
        -- 十字光芒
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, cy - r * 0.55)
        nvgLineTo(vg, sx, cy + r * 0.55)
        nvgMoveTo(vg, sx - r * 0.45, cy)
        nvgLineTo(vg, sx + r * 0.45, cy)
        nvgStrokeWidth(vg, 0.6)
        nvgStrokeColor(vg, nvgRGBAf(gold.r, gold.g, gold.b,
            0.30 + math.sin(t * 3) * 0.12))
        nvgStroke(vg)

    elseif res.type == "shouhun" then
        -- 兽魂：幽蓝火焰/魂魄
        local indigo = InkPalette.indigo
        -- 火焰外形（贝塞尔曲线）
        local flicker = math.sin(t * 4 + (res.x or 0)) * r * 0.04
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, cy + r * 0.30)
        nvgBezierTo(vg,
            sx - r * 0.25, cy + r * 0.10,
            sx - r * 0.20, cy - r * 0.25,
            sx + flicker, cy - r * 0.45)
        nvgBezierTo(vg,
            sx + r * 0.20, cy - r * 0.25,
            sx + r * 0.25, cy + r * 0.10,
            sx, cy + r * 0.30)
        nvgFillColor(vg, nvgRGBAf(indigo.r, indigo.g, indigo.b, 0.45))
        nvgFill(vg)
        -- 内层亮芯
        nvgBeginPath(vg)
        nvgEllipse(vg, sx, cy - r * 0.05, r * 0.08, r * 0.15)
        nvgFillColor(vg, nvgRGBAf(0.7, 0.8, 1.0, 0.50))
        nvgFill(vg)

    elseif res.type == "traceAsh" then
        -- 追迹灰：飘散灰烬弧线 + 散落灰点
        local ashC = InkPalette.inkLight
        nvgLineCap(vg, NVG_ROUND)
        for i = 1, 3 do
            local a0 = (i / 3) * math.pi * 2 + t * 0.5
            local swirl = r * (0.15 + i * 0.08)
            nvgBeginPath(vg)
            nvgArc(vg, sx, cy, swirl, a0, a0 + math.pi * 0.6, NVG_CW)
            nvgStrokeWidth(vg, 1.5 - i * 0.3)
            nvgStrokeColor(vg, nvgRGBAf(ashC.r, ashC.g, ashC.b, 0.40 - i * 0.08))
            nvgStroke(vg)
        end
        -- 散落灰粒
        for i = 1, 5 do
            local hash = ((res.x or 0) * 13 + i * 29) % 100
            local dx = (hash % 20 - 10) * r * 0.04
            local dy = ((hash * 3) % 20 - 10) * r * 0.04
            local driftY = math.sin(t * 1.2 + i * 1.5) * r * 0.04
            nvgBeginPath(vg)
            nvgCircle(vg, sx + dx, cy + dy + driftY, 1.0 + hash % 2)
            nvgFillColor(vg, nvgRGBAf(ashC.r, ashC.g, ashC.b, 0.35))
            nvgFill(vg)
        end

    elseif res.type == "mirrorSand" then
        -- 镇灵砂：菱形晶体簇 + 石青微光
        local az = InkPalette.azure
        for i = 1, 3 do
            local hash = ((res.x or 0) * 7 + i * 41) % 100
            local dx = (i - 2) * r * 0.20 + (hash % 6 - 3) * r * 0.02
            local dy = (hash % 8 - 4) * r * 0.03
            local h = r * (0.22 + (hash % 10) / 60)
            local w = r * 0.08
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + dx, cy + dy - h)
            nvgLineTo(vg, sx + dx + w, cy + dy)
            nvgLineTo(vg, sx + dx, cy + dy + h * 0.4)
            nvgLineTo(vg, sx + dx - w, cy + dy)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBAf(az.r, az.g, az.b, 0.35 + (hash % 15) / 100))
            nvgFill(vg)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(az.r, az.g, az.b, 0.60))
            nvgStroke(vg)
        end
        -- 微光闪烁
        local spark = math.sin(t * 3.0 + (res.x or 0)) * 0.2 + 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, sx + r * 0.05, cy - r * 0.15, r * 0.04)
        nvgFillColor(vg, nvgRGBAf(1, 1, 1, spark))
        nvgFill(vg)

    elseif res.type == "soulCharm" then
        -- 归魂符：符纸矩形 + 朱砂符文线
        local cin = InkPalette.cinnabar
        local pw = InkPalette.paperWarm
        local cw = r * 0.30
        local ch = r * 0.48
        -- 符纸
        nvgBeginPath(vg)
        nvgRect(vg, sx - cw, cy - ch, cw * 2, ch * 2)
        nvgFillColor(vg, nvgRGBAf(pw.r, pw.g, pw.b, 0.85))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
        -- 符文线（竖线 + 横划）
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, cy - ch * 0.70)
        nvgLineTo(vg, sx, cy + ch * 0.50)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.65))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - cw * 0.60, cy - ch * 0.20)
        nvgLineTo(vg, sx + cw * 0.60, cy - ch * 0.20)
        nvgMoveTo(vg, sx - cw * 0.45, cy + ch * 0.15)
        nvgLineTo(vg, sx + cw * 0.45, cy + ch * 0.15)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.50))
        nvgStroke(vg)
        -- 朱砂圆印
        nvgBeginPath(vg)
        nvgCircle(vg, sx, cy + ch * 0.55, r * 0.08)
        nvgFillColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.55))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

--- 绘制撤离点 —— 传送门法阵
function InkRenderer.drawEvacPoint(vg, sx, sy, ppu, t, progress)
    local r = ppu * 0.48
    local jade = InkPalette.jade
    local gold = InkPalette.gold
    local ink = InkPalette.inkStrong

    nvgSave(vg)

    -- 底部翡翠光晕
    local pulseAlpha = 0.18 + math.sin(t * 1.5) * 0.05
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 1.2, jade, pulseAlpha)

    -- 优先贴图
    local handle = imgHandles["evac"]
    if handle then
        local bobY = math.sin(t * 1.2) * ppu * 0.02
        drawIcon(vg, handle, sx, sy + bobY, r, 0.92, 0)
    else
        -- 矢量法阵：双层旋转八卦环 + 中心「归」字暗示
        nvgLineCap(vg, NVG_ROUND)

        -- 外环旋转
        local spin = t * 0.3
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, r * 0.50, spin, spin + math.pi * 1.5, NVG_CW)
        nvgStrokeWidth(vg, 2.0)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.55))
        nvgStroke(vg)

        -- 内环反转
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, r * 0.30, -spin, -spin + math.pi * 1.2, NVG_CW)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.40))
        nvgStroke(vg)

        -- 四向辐射短线
        for i = 0, 3 do
            local a = spin + i * math.pi * 0.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx + math.cos(a) * r * 0.52, sy + math.sin(a) * r * 0.52)
            nvgLineTo(vg, sx + math.cos(a) * r * 0.68, sy + math.sin(a) * r * 0.68)
            nvgStrokeWidth(vg, 1.5)
            nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.45))
            nvgStroke(vg)
        end

        -- 中心墨点
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, r * 0.10)
        nvgFillColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.60))
        nvgFill(vg)
    end

    -- 撤离进度弧
    if progress and progress > 0 then
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, r * 1.15, -math.pi * 0.5,
            -math.pi * 0.5 + math.pi * 2 * progress, NVG_CW)
        nvgStrokeWidth(vg, 3)
        nvgStrokeColor(vg, nvgRGBAf(gold.r, gold.g, gold.b, 0.65))
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

return InkRenderer
