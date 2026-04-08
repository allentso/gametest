--- 水墨世界渲染 - 统一调度 Layer 1/3/4 层
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local Camera = require("systems.Camera")
local Config = require("Config")

local InkRenderer = {}

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

--- 绘制线索
function InkRenderer.drawClue(vg, clue, sx, sy, ppu, t)
    local r = ppu * 0.35
    local cin = InkPalette.cinnabar

    -- 所有线索底层加一圈浅朱砂脉冲提示光圈
    local pulseR = r * (1.2 + math.sin(t * 2.5) * 0.15)
    BrushStrokes.inkWash(vg, sx, sy, pulseR * 0.3, pulseR, cin, 0.10)

    if clue.type == "footprint" then
        -- 4个递减爪印（更大更浓，明确可辨的兽足痕迹）
        for i = 1, 4 do
            local offset = (i - 1) * r * 0.45
            local size = r * (0.65 - i * 0.10)
            local alpha = 0.70 - i * 0.12
            BrushStrokes.inkDotStable(vg,
                sx + offset * 0.6, sy - offset * 0.35,
                size, InkPalette.inkStrong, alpha, i * 13)
        end
        -- 爪印旁飘一缕妖气弧线
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        local drift = math.sin(t * 1.5) * r * 0.15
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - r * 0.2, sy - r * 0.1)
        nvgQuadTo(vg, sx + drift, sy - r * 0.6, sx + r * 0.5, sy - r * 0.8)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.30))
        nvgStroke(vg)
        nvgRestore(vg)

    elseif clue.type == "resonance" then
        -- 3个同心脉冲环（更大、线宽加粗、高alpha石青色）
        for i = 1, 3 do
            local pulse = math.sin(t * 2.5 + i * 0.8) * 0.25 + 0.75
            local cr = r * (0.6 + i * 0.55) * pulse
            nvgSave(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, cr)
            nvgStrokeWidth(vg, 1.5 - i * 0.2)
            nvgStrokeColor(vg, nvgRGBAf(
                InkPalette.azure.r, InkPalette.azure.g, InkPalette.azure.b,
                0.45 - i * 0.10))
            nvgStroke(vg)
            nvgRestore(vg)
        end
        -- 中心高亮石青点
        BrushStrokes.inkDotStable(vg, sx, sy, 3.5,
            InkPalette.azure, 0.55, 77)

    elseif clue.type == "nest" then
        -- 更大的皴法纹理堆 + 浓墨中心 + 朱砂标记
        BrushStrokes.cunTexture(vg, sx, sy, r * 2.0,
            InkPalette.inkStrong, 0.40, (clue.x or 0) * 97 + (clue.y or 0) * 31, 5)
        BrushStrokes.inkDotStable(vg, sx, sy, 4.0, InkPalette.inkStrong, 0.80, 42)
        BrushStrokes.inkDotStable(vg, sx + r * 0.15, sy - r * 0.15, 2.0, cin, 0.50, 43)
    end
end

--- 绘制资源点
function InkRenderer.drawResource(vg, res, sx, sy, ppu, t, playerDist)
    local r = ppu * 0.35

    if res.type == "lingshi" then
        -- 嶙峋岩块（更大皴法区域 + 翡翠光晕强化）
        BrushStrokes.cunTexture(vg, sx, sy, r * 1.6,
            InkPalette.inkStrong, 0.45, (res.x or 0) * 71, 5)
        local glowAlpha = 0.18
        if playerDist and playerDist < 3 then
            glowAlpha = 0.18 + (3 - playerDist) / 3 * 0.25
        end
        BrushStrokes.inkWash(vg, sx, sy - r * 0.2, r * 0.3, r * 1.0,
            InkPalette.jade, glowAlpha)
        -- 顶部翡翠亮点
        local sparkle = math.sin(t * 3) * 0.15 + 0.45
        BrushStrokes.inkDotStable(vg, sx, sy - r * 0.3, 3, InkPalette.jade, sparkle, 88)

    elseif res.type == "tianjing" then
        -- 菱形墨线 + gold 强化晕染 + 旋转
        local rot = t * 0.5
        nvgSave(vg)
        -- 底部光圈
        BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.8, InkPalette.gold, 0.22)
        nvgTranslate(vg, sx, sy)
        nvgRotate(vg, rot)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -r * 0.8)
        nvgLineTo(vg, r * 0.5, 0)
        nvgLineTo(vg, 0, r * 0.8)
        nvgLineTo(vg, -r * 0.5, 0)
        nvgClosePath(vg)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b, 0.65))
        nvgStroke(vg)
        nvgFillColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.15))
        nvgFill(vg)
        nvgRestore(vg)

    else
        -- 追迹灰/镇灵砂/归魂符 — 散落墨点（加大加浓 + 淡彩标记）
        local itemColor = InkPalette.inkMedium
        local accentColor = InkPalette.cinnabar
        if res.type == "traceAsh" then
            accentColor = InkPalette.inkWash
        elseif res.type == "mirrorSand" then
            accentColor = InkPalette.azure
        elseif res.type == "returnCharm" then
            accentColor = InkPalette.gold
        end
        -- 外围光圈
        BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.7, accentColor, 0.15)
        -- 散落墨点群（更大更浓）
        for i = 1, 5 do
            local hash = ((res.x or 0) * 7 + (res.y or 0) * 13 + i * 31) % 100
            local dx = (hash % 20 - 10) * r * 0.10
            local dy = ((hash * 7) % 20 - 10) * r * 0.10
            BrushStrokes.inkDotStable(vg, sx + dx, sy + dy,
                2.5 + (hash % 3), itemColor, 0.45, hash)
        end
        -- 中心标记点
        BrushStrokes.inkDotStable(vg, sx, sy, 3.5, accentColor, 0.55, 55)
    end
end

--- 绘制撤离点
function InkRenderer.drawEvacPoint(vg, sx, sy, ppu, t, progress)
    local r = ppu * 0.4

    nvgSave(vg)
    -- 3层同心jade描边环
    for i = 1, 3 do
        local pulse = 1.0 + math.sin(t * 1.5 + i * 0.6) * 0.05
        local ringR = r * (0.6 + i * 0.25) * pulse
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, ringR)
        nvgStrokeWidth(vg, 1.2 - i * 0.2)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b,
            0.35 - (i - 1) * 0.08))
        nvgStroke(vg)
    end

    -- 中心gold墨点
    local dotAlpha = 0.5 + math.sin(t * 2) * 0.2
    BrushStrokes.inkDotStable(vg, sx, sy, 3, InkPalette.gold, dotAlpha, 99)

    -- 撤离进度弧
    if progress and progress > 0 then
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, r * 1.2, -math.pi * 0.5,
            -math.pi * 0.5 + math.pi * 2 * progress, NVG_CW)
        nvgStrokeWidth(vg, 3)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.65))
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

return InkRenderer
