--- 异兽水墨绘制 - 白描骨架体系：每种异兽具象化水墨形态
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")

local BeastRenderer = {}

--- 异兽形态定义（水墨白描画法）
BeastRenderer.shapes = {}

------------------------------------------------------------
-- 白描原语：不规则闭合曲线轮廓（替代标准椭圆）
------------------------------------------------------------

--- 绘制不规则闭合曲线轮廓（白描描边）
--- pts: {{x,y}, {x,y}, ...} 闭合点序列
--- 用贝塞尔曲线平滑连接，边缘带粗细变化
local function drawWhiteSketch(vg, pts, cx, cy, color, fillAlpha, strokeAlpha, strokeW, seed)
    seed = seed or 0
    strokeW = strokeW or 1.2
    local n = #pts
    if n < 3 then return end

    -- 填充
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + pts[1][1], cy + pts[1][2])
    for i = 2, n do
        local prev = pts[i - 1]
        local curr = pts[i]
        local mx = (prev[1] + curr[1]) * 0.5
        local my = (prev[2] + curr[2]) * 0.5
        nvgQuadTo(vg, cx + prev[1], cy + prev[2], cx + mx, cy + my)
    end
    -- 闭合
    local last = pts[n]
    local first = pts[1]
    local mx = (last[1] + first[1]) * 0.5
    local my = (last[2] + first[2]) * 0.5
    nvgQuadTo(vg, cx + last[1], cy + last[2], cx + mx, cy + my)
    nvgClosePath(vg)

    if fillAlpha > 0 then
        nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, fillAlpha))
        nvgFill(vg)
    end

    -- 描边（分段画，模拟粗细变化）
    if strokeAlpha > 0 then
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        for i = 1, n do
            local p1 = pts[i]
            local p2 = pts[i % n + 1]
            -- 飞白概率：10% 跳过
            local hash = (seed * 7 + i * 31) % 100
            if hash > 10 then
                local thickVar = 1.0 + ((hash % 40) - 20) / 100  -- ±20% 粗细
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx + p1[1], cy + p1[2])
                nvgLineTo(vg, cx + p2[1], cy + p2[2])
                nvgStrokeWidth(vg, strokeW * thickVar)
                nvgStrokeColor(vg, nvgRGBAf(color.r, color.g, color.b, strokeAlpha))
                nvgStroke(vg)
            end
        end
    end
end

------------------------------------------------------------
-- 主绘制入口
------------------------------------------------------------

function BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
    local r = (beast.bodySize or 0.55) * ppu
    local qColor = InkPalette.qualColor(beast.quality)

    -- 呼吸缩放（0.8s 循环）
    local breathe = 1.0 + math.sin(t * math.pi * 2 / 0.8) * 0.03

    nvgSave(vg)
    nvgTranslate(vg, sx, sy)
    nvgScale(vg, breathe, breathe)
    nvgTranslate(vg, -sx, -sy)

    -- 品质光晕
    BeastRenderer.drawQualityGlow(vg, beast.quality, sx, sy, r, qColor, t)

    -- 朝向指示扇形（视野锥）
    BeastRenderer.drawFacingCone(vg, beast, sx, sy, r, t)

    -- 主体形态
    local shapeFn = BeastRenderer.shapes[beast.type]
    if shapeFn then
        shapeFn(vg, sx, sy, r, t, beast)
    else
        BeastRenderer.drawDefaultShape(vg, sx, sy, r, t, beast)
    end

    -- 状态特效 + 头顶图标
    if beast.aiState == "alert" then
        BeastRenderer.drawAlertMark(vg, sx, sy, r, t)
    elseif beast.aiState == "warn" then
        BeastRenderer.drawWarnMark(vg, sx, sy, r, t)
    elseif beast.aiState == "chase" then
        BeastRenderer.drawChaseMark(vg, sx, sy, r, t)
    elseif beast.aiState == "stunned" or beast.aiState == "frozen" then
        BeastRenderer.drawStunnedMark(vg, sx, sy, r, t)
    elseif beast.aiState == "flee" then
        BeastRenderer.drawSpeedLines(vg, beast, sx, sy, r, t)
    end

    -- 异兽HP条（有HP且非满血时显示）
    if beast.hp and beast.maxHP and beast.hp < beast.maxHP and beast.hp > 0 then
        BeastRenderer.drawBeastHPBar(vg, beast, sx, sy, r)
    end

    -- 攻击预警视觉（warmup阶段）
    if beast.aiState == "attack" and beast.attackTimer and beast.attackTimer > 0 then
        BeastRenderer.drawAttackWarning(vg, beast, sx, sy, r, ppu, t)
    end

    nvgRestore(vg)
end

--- 品质光晕
function BeastRenderer.drawQualityGlow(vg, quality, sx, sy, r, color, t)
    if quality == "R" then return end

    if quality == "SR" then
        local pulse = 1.0 + math.sin(t * 2) * 0.08
        BrushStrokes.inkWash(vg, sx, sy, r * 0.8 * pulse, r * 2.0 * pulse,
            color, 0.12)
    elseif quality == "SSR" then
        for i = 1, 3 do
            local scale = 1.0 + (i - 1) * 0.4
            local pulse = 1.0 + math.sin(t * 2 + i * 0.7) * 0.06
            BrushStrokes.inkWash(vg, sx, sy,
                r * scale * pulse, r * (scale + 0.8) * pulse,
                color, 0.10 - (i - 1) * 0.02)
        end
        local particleCount = 6
        for i = 1, particleCount do
            local angle = (i / particleCount) * math.pi * 2 + t * 2.0
            local dist = r * 2.2 + math.sin(t * 3 + i * 1.2) * r * 0.3
            local px = sx + math.cos(angle) * dist
            local py = sy + math.sin(angle) * dist
            BrushStrokes.inkDotStable(vg, px, py, 1.5,
                InkPalette.gold, 0.30, i * 7)
        end
    end
end

--- 朝向扇形视野锥
function BeastRenderer.drawFacingCone(vg, beast, sx, sy, r, t)
    local facing = beast.facing or 0
    local coneAngle = math.pi / 3
    local coneR = r * 2.5
    local alpha = 0.07 + math.sin(t * 1.5) * 0.02

    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy)
    nvgArc(vg, sx, sy, coneR, -facing - coneAngle, -facing + coneAngle, NVG_CW)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, alpha))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 默认异兽形态（白描不规则体，替代旧版椭圆）
function BeastRenderer.drawDefaultShape(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local seed = beast.facing and math.floor(beast.facing * 100) or 0

    -- 不规则六边形轮廓
    local pts = {}
    for i = 1, 6 do
        local angle = (i - 1) / 6 * math.pi * 2 - math.pi / 2
        local hash = (seed * 7 + i * 31) % 100
        local rVar = r * (0.55 + hash / 300)  -- 0.55-0.88 r
        table.insert(pts, { math.cos(angle) * rVar, math.sin(angle) * rVar * 0.75 })
    end
    drawWhiteSketch(vg, pts, sx, sy, ink, 0.45, 0.65, 1.2, seed)

    -- 眼睛
    local facing = beast.facing or 0
    local eyeDist = r * 0.3
    local eyeX = sx + math.cos(-facing) * eyeDist
    local eyeY = sy + math.sin(-facing) * eyeDist
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, eyeX, eyeY, r * 0.07)
    nvgFillColor(vg, nvgRGBAf(0.96, 0.93, 0.87, 0.85))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 警觉标记 "!"
function BeastRenderer.drawAlertMark(vg, sx, sy, r, t)
    local bounce = math.sin(t * 4) * r * 0.15
    local markY = sy - r * 1.5 + bounce

    nvgSave(vg)
    nvgFontSize(vg, r * 1.5)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.90))
    nvgText(vg, sx, markY, "!")
    nvgRestore(vg)
end

--- 逃跑速度线
function BeastRenderer.drawSpeedLines(vg, beast, sx, sy, r, t)
    local facing = beast.facing or 0
    local backAngle = facing + math.pi

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 3 do
        local spread = (i - 2) * 0.25
        local angle = backAngle + spread
        local len = r * (1.2 - i * 0.2)
        local startX = sx + math.cos(-angle) * r * 0.6
        local startY = sy + math.sin(-angle) * r * 0.6
        local endX = startX + math.cos(-angle) * len
        local endY = startY + math.sin(-angle) * len

        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, startY)
        nvgLineTo(vg, endX, endY)
        nvgStrokeWidth(vg, 1.2 - i * 0.2)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.45 - i * 0.12))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- 警告标记 "×"（warn状态，领地警告）
function BeastRenderer.drawWarnMark(vg, sx, sy, r, t)
    local shake = math.sin(t * 6) * r * 0.08
    local markY = sy - r * 1.5 + shake
    local markSize = r * 0.35

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 墨色叉号
    local ink = InkPalette.inkStrong
    local alpha = 0.75 + math.sin(t * 3) * 0.15
    nvgStrokeWidth(vg, 2.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, alpha))
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - markSize, markY - markSize)
    nvgLineTo(vg, sx + markSize, markY + markSize)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + markSize, markY - markSize)
    nvgLineTo(vg, sx - markSize, markY + markSize)
    nvgStroke(vg)
    nvgRestore(vg)
end

--- 追击标记 "火焰"图标（chase状态）
function BeastRenderer.drawChaseMark(vg, sx, sy, r, t)
    local markY = sy - r * 1.6
    local flicker = math.sin(t * 8) * r * 0.05

    nvgSave(vg)
    -- 火焰形状（简化水墨火焰：3个尖瓣）
    local cin = InkPalette.cinnabar
    local alpha = 0.70 + math.sin(t * 5) * 0.20

    for i = -1, 1 do
        local fx = sx + i * r * 0.15
        local baseY = markY + r * 0.2
        local tipY = markY - r * 0.25 + flicker * (1 + math.abs(i) * 0.5)
        nvgBeginPath(vg)
        nvgMoveTo(vg, fx - r * 0.08, baseY)
        nvgQuadTo(vg, fx - r * 0.02, markY + r * 0.05, fx, tipY)
        nvgQuadTo(vg, fx + r * 0.02, markY + r * 0.05, fx + r * 0.08, baseY)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, alpha - math.abs(i) * 0.15))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

--- 眩晕/冻结标记 "ZZZ"（stunned/frozen状态）
function BeastRenderer.drawStunnedMark(vg, sx, sy, r, t)
    local markY = sy - r * 1.5
    local bob = math.sin(t * 2) * r * 0.06

    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 三个"Z"，从小到大渐远
    local ink = InkPalette.inkMedium
    for i = 1, 3 do
        local zx = sx + (i - 1) * r * 0.25 - r * 0.15
        local zy = markY - (i - 1) * r * 0.2 + bob * i * 0.3
        local fontSize = r * (0.5 + i * 0.15)
        local alpha = 0.55 - (i - 1) * 0.12
        nvgFontSize(vg, fontSize)
        nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, alpha))
        nvgText(vg, zx, zy, "Z")
    end
    nvgRestore(vg)
end

--- 异兽HP条（伤血后显示在身体下方）
function BeastRenderer.drawBeastHPBar(vg, beast, sx, sy, r)
    local barW = r * 1.6
    local barH = 3
    local barX = sx - barW * 0.5
    local barY = sy + r * 0.8

    local hpFrac = beast.hp / beast.maxHP
    local P = InkPalette

    nvgSave(vg)
    -- 底框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 1.5)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40))
    nvgFill(vg)
    -- 血量填充
    local fillColor = hpFrac > 0.3 and P.cinnabar or P.gold
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpFrac, barH, 1.5)
    nvgFillColor(vg, nvgRGBAf(fillColor.r, fillColor.g, fillColor.b, 0.70))
    nvgFill(vg)
    nvgRestore(vg)
end

--- 攻击预警视觉（warmup阶段绘制方向/范围提示）
function BeastRenderer.drawAttackWarning(vg, beast, sx, sy, r, ppu, t)
    local atk = beast.currentAttack
    if not atk then return end
    local warmup = atk.warmup or 0
    if warmup <= 0 then return end -- warmup=0 = 无预警（偷袭类）

    -- 进度：0→1，1 表示即将命中
    local progress = math.min(1.0, 1.0 - (beast.attackTimer or 0) / warmup)

    -- 闪烁加速：进度越大闪烁越快
    local flashHz = 3 + progress * 8  -- 3→11 Hz
    local flash = 0.5 + 0.5 * math.sin(t * flashHz * math.pi * 2)
    local baseAlpha = 0.15 + progress * 0.45 -- 0.15→0.60

    local facing = beast.facing or 0
    local P = InkPalette

    if atk.aoeType == "line" then
        ----------------------------------------
        -- 线型预警：方向箭头 + 射线
        ----------------------------------------
        local range = (atk.range or 3.0) * ppu
        local arrowLen = range * progress  -- 逐渐延伸

        -- 射线方向
        local dx = math.cos(facing)
        local dy = math.sin(facing)

        -- 危险射线（从兽身延伸）
        local lineAlpha = baseAlpha * flash
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)

        -- 主线
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, sx + dx * arrowLen, sy + dy * arrowLen)
        nvgStrokeWidth(vg, 2.5 + progress * 2.0)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, lineAlpha))
        nvgStroke(vg)

        -- 箭头三角
        if progress > 0.3 then
            local tipX = sx + dx * arrowLen
            local tipY = sy + dy * arrowLen
            local perpX = -dy  -- 垂直方向
            local perpY = dx
            local headSize = (6 + progress * 6)

            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX + dx * headSize, tipY + dy * headSize)
            nvgLineTo(vg, tipX + perpX * headSize * 0.6, tipY + perpY * headSize * 0.6)
            nvgLineTo(vg, tipX - perpX * headSize * 0.6, tipY - perpY * headSize * 0.6)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, lineAlpha * 0.8))
            nvgFill(vg)
        end

        nvgRestore(vg)

    elseif atk.aoeType == "circle" then
        ----------------------------------------
        -- 圆形AOE预警：扩散裂纹圆 + 中心震波
        ----------------------------------------
        local aoeR = (atk.aoeRadius or 2.0) * ppu
        local expandR = aoeR * progress  -- 逐渐扩大到满半径

        nvgSave(vg)

        -- 扩散圆环（水墨裂纹感）
        local ringAlpha = baseAlpha * flash * 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, expandR)
        nvgStrokeWidth(vg, 1.5 + progress * 1.5)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, ringAlpha))
        nvgStroke(vg)

        -- 内部填充（半透明危险区域）
        if progress > 0.4 then
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, expandR)
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b,
                (progress - 0.4) * 0.15 * flash))
            nvgFill(vg)
        end

        -- 裂纹线条（从中心向外放射）
        local crackCount = 6
        nvgLineCap(vg, NVG_ROUND)
        for i = 1, crackCount do
            local angle = (i - 1) / crackCount * math.pi * 2 + t * 0.5
            local crackLen = expandR * (0.5 + progress * 0.5)
            -- 锯齿状裂纹
            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            local steps = 3
            for s = 1, steps do
                local frac = s / steps
                local jitter = math.sin(s * 7 + i * 13 + t * 3) * expandR * 0.08
                local px = sx + math.cos(angle) * crackLen * frac + math.cos(angle + math.pi / 2) * jitter
                local py = sy + math.sin(angle) * crackLen * frac + math.sin(angle + math.pi / 2) * jitter
                nvgLineTo(vg, px, py)
            end
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b,
                ringAlpha * 0.6))
            nvgStroke(vg)
        end

        nvgRestore(vg)

    else
        ----------------------------------------
        -- 近战/扇形预警：扇形危险区
        ----------------------------------------
        local range = (atk.range or 2.0) * ppu
        local arcHalf = math.rad((atk.arc or 60) / 2)
        local expandRange = range * progress

        nvgSave(vg)

        -- 扇形填充
        local arcAlpha = baseAlpha * flash * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        -- NanoVG 角度：facing 从 atan2 而来，需转为屏幕角度
        nvgArc(vg, sx, sy, expandRange, facing - arcHalf, facing + arcHalf, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, arcAlpha))
        nvgFill(vg)

        -- 扇形描边
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgArc(vg, sx, sy, expandRange, facing - arcHalf, facing + arcHalf, NVG_CW)
        nvgClosePath(vg)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b,
            arcAlpha * 1.5))
        nvgStroke(vg)

        nvgRestore(vg)
    end

    -- 通用：预警 "!" 字符脉冲（进度>60%时显示）
    if progress > 0.6 then
        local bangAlpha = (progress - 0.6) / 0.4 * flash * 0.8
        local bangY = sy - r * 1.8
        nvgSave(vg)
        nvgFontSize(vg, r * (1.0 + progress * 0.5))
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, bangAlpha))
        nvgText(vg, sx, bangY, "!")
        nvgRestore(vg)
    end
end

--- 偷袭成功 "袭" 字闪现
function BeastRenderer.drawAmbushFlash(vg, sx, sy, r, elapsed)
    if elapsed > 0.5 then return end
    local alpha = 1.0 - elapsed / 0.5
    nvgSave(vg)
    nvgFontSize(vg, r * 1.2)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, alpha))
    nvgText(vg, sx, sy - r * 0.5, "袭")
    nvgRestore(vg)
end

------------------------------------------------------------
-- 具体异兽形态：白描骨架体系
------------------------------------------------------------

-- 001 玄狐 — 灵巧狐形，大耳 + 飞白尾
BeastRenderer.shapes["001"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    -- 躯干：梭形不规则体
    local body = {
        {-r * 0.6,  r * 0.15},
        {-r * 0.3, -r * 0.35},
        { r * 0.1, -r * 0.4},
        { r * 0.7, -r * 0.15},
        { r * 0.65, r * 0.2},
        { r * 0.1,  r * 0.35},
        {-r * 0.3,  r * 0.3},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.45, 0.60, 1.3, 101)

    -- 双耳（三角尖耳，飞白描边）
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    for side = -1, 1, 2 do
        local earBase = r * 0.25
        local earTip = r * 0.5
        local bx = sx + side * r * 0.2
        local by = sy - r * 0.35
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx - side * earBase * 0.3, by)
        nvgLineTo(vg, bx + side * earBase * 0.15, by - earTip)
        nvgLineTo(vg, bx + side * earBase * 0.5, by + earBase * 0.1)
        nvgStrokeWidth(vg, 1.4)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
        nvgStroke(vg)
        -- 耳内填充
        nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.30))
        nvgFill(vg)
    end

    -- 尾巴：飞白弧线
    local tailPhase = math.sin(t * 2) * r * 0.12
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.55, sy + r * 0.1)
    nvgBezierTo(vg,
        sx - r * 1.1, sy - r * 0.1 + tailPhase,
        sx - r * 1.3, sy - r * 0.5 + tailPhase,
        sx - r * 0.8, sy - r * 0.6)
    nvgStrokeWidth(vg, 2.5)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgStroke(vg)

    -- 眼睛：朱砂点
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.35
    local ey = sy + math.sin(-facing) * r * 0.25
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.06, InkPalette.cinnabar, 0.70, 7)

    nvgRestore(vg)
end

-- 002 噬天蟒 — 蜿蜒蛇形，S型身躯
BeastRenderer.shapes["002"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local wave = math.sin(t * 2) * r * 0.15

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 蛇身：粗→细渐变的 S 形
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.9, sy + wave * 0.5)
    nvgBezierTo(vg,
        sx - r * 0.3, sy - r * 0.45 + wave,
        sx + r * 0.3, sy + r * 0.45 - wave,
        sx + r * 0.9, sy - wave * 0.3)
    nvgStrokeWidth(vg, r * 0.35)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)

    -- 蛇头（三角形）
    local headX = sx + r * 0.9
    local headY = sy - wave * 0.3
    nvgBeginPath(vg)
    nvgMoveTo(vg, headX, headY - r * 0.18)
    nvgLineTo(vg, headX + r * 0.35, headY)
    nvgLineTo(vg, headX, headY + r * 0.18)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.60))
    nvgFill(vg)

    -- 蛇信（朱砂叉舌）
    nvgBeginPath(vg)
    nvgMoveTo(vg, headX + r * 0.3, headY)
    nvgLineTo(vg, headX + r * 0.5, headY - r * 0.08)
    nvgMoveTo(vg, headX + r * 0.3, headY)
    nvgLineTo(vg, headX + r * 0.5, headY + r * 0.08)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.50))
    nvgStroke(vg)

    -- 鳞纹（短斜线）
    for i = 1, 5 do
        local frac = (i - 0.5) / 5
        local px = sx + (frac * 2 - 1) * r * 0.7
        local py = sy + math.sin(frac * math.pi + t * 2) * r * 0.2
        local hash = (i * 31) % 100
        nvgBeginPath(vg)
        nvgMoveTo(vg, px - 2, py - 2)
        nvgLineTo(vg, px + 2, py + 1)
        nvgStrokeWidth(vg, 0.7)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.25))
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

-- 003 雷翼鹏 — 展翅猛禽，宽翼 + 尾羽
BeastRenderer.shapes["003"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local wingFlap = math.sin(t * 3) * r * 0.18

    nvgSave(vg)
    -- 身体：纺锤形
    local body = {
        { 0, -r * 0.35},
        { r * 0.35, -r * 0.1},
        { r * 0.3,  r * 0.2},
        { 0,  r * 0.4},
        {-r * 0.3,  r * 0.2},
        {-r * 0.35, -r * 0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.45, 0.55, 1.2, 103)

    -- 双翼（粗→细飞白弧线）
    nvgLineCap(vg, NVG_ROUND)
    for side = -1, 1, 2 do
        -- 主翼
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.2, sy - r * 0.05)
        nvgQuadTo(vg,
            sx + side * r * 0.9, sy - r * 0.7 - wingFlap,
            sx + side * r * 1.3, sy - r * 0.15 + wingFlap * 0.5)
        nvgStrokeWidth(vg, 2.2)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
        nvgStroke(vg)
        -- 翼尖羽
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 1.3, sy - r * 0.15 + wingFlap * 0.5)
        nvgLineTo(vg, sx + side * r * 1.1, sy + r * 0.1)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
    end

    -- 尾羽
    for i = -1, 1 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + i * r * 0.1, sy + r * 0.35)
        nvgLineTo(vg, sx + i * r * 0.15, sy + r * 0.75)
        nvgStrokeWidth(vg, 1.0 + math.abs(i) * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end

    -- 喙
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy - r * 0.35)
    nvgLineTo(vg, sx + r * 0.12, sy - r * 0.55)
    nvgLineTo(vg, sx - r * 0.05, sy - r * 0.42)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.65))
    nvgFill(vg)

    nvgRestore(vg)
end

-- 004 白泽 — 庄重神兽，方正身躯 + 头角 + 金辉
BeastRenderer.shapes["004"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    nvgSave(vg)
    -- 身体：不规则方正体
    local body = {
        {-r * 0.6, -r * 0.4},
        {-r * 0.1, -r * 0.5},
        { r * 0.5, -r * 0.45},
        { r * 0.65, -r * 0.1},
        { r * 0.6,  r * 0.35},
        {-r * 0.1,  r * 0.4},
        {-r * 0.55, r * 0.3},
        {-r * 0.65, 0},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.40, 0.60, 1.3, 104)

    -- 头角（向上的弯曲线条）
    nvgLineCap(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.1, sy - r * 0.48)
    nvgQuadTo(vg, sx, sy - r * 1.0, sx + r * 0.15, sy - r * 0.85)
    nvgStrokeWidth(vg, 1.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgStroke(vg)

    -- 四肢短线
    local legs = {{-0.4, 0.35}, {0.3, 0.35}, {-0.35, 0.3}, {0.4, 0.3}}
    for _, l in ipairs(legs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1] * r, sy + l[2] * r)
        nvgLineTo(vg, sx + l[1] * r * 1.1, sy + r * 0.6)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end

    -- 角顶金辉
    BrushStrokes.inkWash(vg, sx, sy - r * 0.9, r * 0.1, r * 0.35,
        InkPalette.gold, 0.18)

    nvgRestore(vg)
end

-- 005 石灵 — 嶙峋岩形，皴法堆叠轮廓
BeastRenderer.shapes["005"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local seed = beast.facing and math.floor(beast.facing * 100) or 0

    nvgSave(vg)
    -- 岩体轮廓：不规则多边形
    local pts = {}
    local numPts = 7
    for i = 1, numPts do
        local angle = (i - 1) / numPts * math.pi * 2 - math.pi / 2
        local hash = (seed * 11 + i * 23) % 100
        local rVar = r * (0.5 + hash / 200)
        table.insert(pts, { math.cos(angle) * rVar, math.sin(angle) * rVar * 0.85 })
    end
    drawWhiteSketch(vg, pts, sx, sy, ink, 0.35, 0.55, 1.5, seed)

    -- 内部皴法纹理
    BrushStrokes.cunTexture(vg, sx, sy, r * 0.7,
        ink, 0.28, seed, 6)

    -- 岩缝中的翡翠微光（核心光点，标识生命）
    local glowPulse = 0.15 + math.sin(t * 2.5) * 0.08
    BrushStrokes.inkWash(vg, sx, sy - r * 0.1, r * 0.08, r * 0.3,
        InkPalette.jade, glowPulse)

    -- 眼睛：缝隙中的光点
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.2
    local ey = sy + math.sin(-facing) * r * 0.15 - r * 0.1
    nvgBeginPath(vg)
    nvgCircle(vg, ex, ey, r * 0.06)
    nvgFillColor(vg, nvgRGBAf(InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b, 0.80))
    nvgFill(vg)

    nvgRestore(vg)
end

-- 006 水蛟 — 流线形水中龙，波浪身形
BeastRenderer.shapes["006"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local wave = math.sin(t * 2.5) * r * 0.12

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)

    -- 蛟身：流线贝塞尔（粗中段→细尾）
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.85, sy + wave)
    nvgBezierTo(vg,
        sx - r * 0.3, sy - r * 0.3 + wave,
        sx + r * 0.3, sy + r * 0.3 - wave,
        sx + r * 0.85, sy + wave * 0.3)
    nvgStrokeWidth(vg, r * 0.28)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.48))
    nvgStroke(vg)

    -- 龙角
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + r * 0.7, sy + wave * 0.3 - r * 0.1)
    nvgLineTo(vg, sx + r * 0.65, sy + wave * 0.3 - r * 0.35)
    nvgMoveTo(vg, sx + r * 0.55, sy + wave * 0.3 - r * 0.08)
    nvgLineTo(vg, sx + r * 0.5, sy + wave * 0.3 - r * 0.3)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)

    -- 尾鳍（扇形扫出）
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.8, sy + wave)
    nvgQuadTo(vg, sx - r * 1.1, sy - r * 0.3, sx - r * 1.0, sy - r * 0.15)
    nvgMoveTo(vg, sx - r * 0.8, sy + wave)
    nvgQuadTo(vg, sx - r * 1.1, sy + r * 0.35, sx - r * 1.0, sy + r * 0.2)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
    nvgStroke(vg)

    -- 水花晕
    BrushStrokes.inkWash(vg, sx, sy, r * 0.3, r * 1.3,
        InkPalette.azure, 0.10)

    nvgRestore(vg)
end

-- 007 风鸣 — 无形之鸟，唯闻其声，不见其影（半透明气旋+音波纹）
BeastRenderer.shapes["007"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    nvgSave(vg)

    -- 气旋核心：极淡的椭圆体（几乎透明的风之凝聚）
    local breathe = math.sin(t * 3) * r * 0.05
    local coreR = r * 0.35 + breathe
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy, coreR, coreR * 0.8)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.12))
    nvgFill(vg)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.25))
    nvgStroke(vg)

    -- 旋风线条（围绕核心的弧形飞白，表达风的旋转）
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 4 do
        local baseAngle = (i - 1) / 4 * math.pi * 2 + t * 2.5
        local dist = r * (0.45 + i * 0.12)
        local arcLen = math.pi * 0.6
        local startA = baseAngle
        local endA = baseAngle + arcLen
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, dist, startA, endA, NVG_CW)
        local alpha = 0.35 - i * 0.06
        nvgStrokeWidth(vg, 1.8 - i * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, alpha))
        nvgStroke(vg)
    end

    -- 音波纹（同心弧线，模拟鸣叫声波，仅绘制前方扇区）
    local facing = beast.facing or 0
    local wavePhase = t * 4
    for i = 1, 3 do
        local waveR = r * (0.6 + i * 0.35) + math.sin(wavePhase + i) * r * 0.05
        local halfArc = math.pi / 5
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, waveR, -facing - halfArc, -facing + halfArc, NVG_CW)
        local alpha = 0.30 - i * 0.08
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, alpha))
        nvgStroke(vg)
    end

    -- 风之眼（核心位置一点微光，标识生命）
    local eyeX = sx + math.cos(-facing) * r * 0.15
    local eyeY = sy + math.sin(-facing) * r * 0.1
    BrushStrokes.inkDotStable(vg, eyeX, eyeY, r * 0.05,
        InkPalette.jade, 0.55, 77)

    -- 风场淡晕
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.7,
        InkPalette.jade, 0.06)

    nvgRestore(vg)
end

-- 008 岩甲龟 — 厚重龟壳 + 四肢 + 头
BeastRenderer.shapes["008"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    nvgSave(vg)
    -- 龟壳：不规则六边形，皴法纹理
    local shell = {
        {-r * 0.2, -r * 0.55},
        { r * 0.3, -r * 0.5},
        { r * 0.6, -r * 0.1},
        { r * 0.5,  r * 0.35},
        {-r * 0.1,  r * 0.45},
        {-r * 0.55, r * 0.25},
        {-r * 0.6, -r * 0.15},
    }
    drawWhiteSketch(vg, shell, sx, sy, ink, 0.40, 0.60, 1.5, 108)

    -- 壳纹（内部皴法）
    BrushStrokes.cunTexture(vg, sx, sy, r * 0.4,
        ink, 0.18, 108, 4)

    -- 四肢（短促墨线）
    nvgLineCap(vg, NVG_ROUND)
    local limbs = {
        {-r * 0.5, -r * 0.25, -r * 0.75, -r * 0.45},
        { r * 0.45, -r * 0.2,  r * 0.7, -r * 0.4},
        {-r * 0.45,  r * 0.3, -r * 0.7,  r * 0.5},
        { r * 0.4,   r * 0.3,  r * 0.65,  r * 0.5},
    }
    for _, l in ipairs(limbs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1], sy + l[2])
        nvgLineTo(vg, sx + l[3], sy + l[4])
        nvgStrokeWidth(vg, 2.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end

    -- 头部（小圆 + 眼）
    local facing = beast.facing or 0
    local headX = sx + math.cos(-facing) * r * 0.55
    local headY = sy + math.sin(-facing) * r * 0.35
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.18)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgFill(vg)
    -- 眼
    nvgBeginPath(vg)
    nvgCircle(vg, headX + math.cos(-facing) * r * 0.08, headY + math.sin(-facing) * r * 0.05, r * 0.04)
    nvgFillColor(vg, nvgRGBAf(0.96, 0.93, 0.87, 0.80))
    nvgFill(vg)

    nvgRestore(vg)
end

-- 009 冰蚕 — 微小蚕形，晶莹剔透，吐丝结茧（体小如拇指）
BeastRenderer.shapes["009"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    nvgSave(vg)

    -- 蚕身：由多个椭圆节段组成的柔软蠕动体
    local segments = 5
    local segLen = r * 0.22
    local wriggle = math.sin(t * 3) * r * 0.04
    nvgLineCap(vg, NVG_ROUND)

    -- 每一节身体
    for i = 1, segments do
        local frac = (i - 1) / (segments - 1) -- 0~1
        local offsetX = (frac - 0.5) * r * 1.0
        local offsetY = math.sin(frac * math.pi * 2 + t * 3) * wriggle
        local segR = r * (0.18 - math.abs(frac - 0.5) * 0.12) -- 中间粗两头细
        nvgBeginPath(vg)
        nvgEllipse(vg, sx + offsetX, sy + offsetY, segR, segR * 0.7)
        -- 晶莹半透明填充（冰蓝色调）
        nvgFillColor(vg, nvgRGBAf(InkPalette.azure.r, InkPalette.azure.g, InkPalette.azure.b, 0.15 + frac * 0.05))
        nvgFill(vg)
        nvgStrokeWidth(vg, 0.8)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
    end

    -- 头部（最前端稍大的圆）
    local headX = sx + r * 0.5
    local headY = sy + math.sin(t * 3) * wriggle
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.12)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgFill(vg)

    -- 眼睛（微小冰蓝光点）
    local facing = beast.facing or 0
    BrushStrokes.inkDotStable(vg,
        headX + math.cos(-facing) * r * 0.06,
        headY + math.sin(-facing) * r * 0.04,
        r * 0.03, InkPalette.azure, 0.70, 99)

    -- 寒丝（头部向前延伸的细线，模拟吐丝）
    local silkSway = math.sin(t * 2) * r * 0.06
    nvgBeginPath(vg)
    nvgMoveTo(vg, headX + r * 0.1, headY)
    nvgBezierTo(vg,
        headX + r * 0.3, headY - r * 0.1 + silkSway,
        headX + r * 0.5, headY + silkSway,
        headX + r * 0.6, headY - r * 0.05 + silkSway)
    nvgStrokeWidth(vg, 0.5)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.azure.r, InkPalette.azure.g, InkPalette.azure.b, 0.30))
    nvgStroke(vg)

    -- 冰晶微光（体表折射光效）
    for i = 1, 3 do
        local sparkX = sx + (i / 4 - 0.5) * r * 0.8
        local sparkY = sy + math.sin(t * 4 + i * 2) * r * 0.06
        local sparkAlpha = 0.3 + math.sin(t * 5 + i) * 0.15
        BrushStrokes.inkDotStable(vg, sparkX, sparkY, r * 0.025,
            InkPalette.azure, sparkAlpha, 90 + i)
    end

    -- 冰气淡晕
    BrushStrokes.inkWash(vg, sx, sy, r * 0.15, r * 0.5,
        InkPalette.azure, 0.06)

    nvgRestore(vg)
end

-- 010 墨鸦 — 漆黑如墨，飞则流焰，落则成灰（鸦形鸟，火焰尾迹）
BeastRenderer.shapes["010"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong

    nvgSave(vg)

    -- 鸦身：紧凑的鸟形轮廓（比雷翼小，更圆润）
    local body = {
        { r * 0.35, -r * 0.15},  -- 喙根
        { r * 0.2, -r * 0.4},    -- 头顶
        {-r * 0.1, -r * 0.42},   -- 后脑
        {-r * 0.4, -r * 0.3},    -- 背部
        {-r * 0.5, -r * 0.05},   -- 尾根
        {-r * 0.35, r * 0.25},   -- 腹尾
        { 0, r * 0.3},           -- 腹部
        { r * 0.25, r * 0.15},   -- 胸部
    }
    -- 浓墨填充（漆黑），描边也深
    drawWhiteSketch(vg, body, sx, sy, ink, 0.65, 0.75, 1.4, 110)

    nvgLineCap(vg, NVG_ROUND)

    -- 尖喙（朱砂色尖端，表示火性）
    local facing = beast.facing or 0
    local beakTipX = sx + r * 0.55
    local beakTipY = sy - r * 0.05
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + r * 0.35, sy - r * 0.12)
    nvgLineTo(vg, beakTipX, beakTipY)
    nvgLineTo(vg, sx + r * 0.35, sy + r * 0.02)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.70))
    nvgFill(vg)

    -- 翅膀（收拢状态，两片弧线紧贴身体）
    for side = -1, 1, 2 do
        local wingFlutter = math.sin(t * 2.5 + side) * r * 0.04
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - r * 0.1, sy + side * r * 0.05)
        nvgBezierTo(vg,
            sx - r * 0.3, sy + side * r * 0.3 + wingFlutter,
            sx - r * 0.5, sy + side * r * 0.2 + wingFlutter,
            sx - r * 0.55, sy + side * r * 0.05)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
        nvgStroke(vg)
    end

    -- 火焰尾迹（"飞则流焰" — 尾部拖出朱砂焰光）
    local flamePhase = t * 5
    for i = 1, 4 do
        local frac = i / 4
        local flameX = sx - r * (0.5 + frac * 0.6)
        local flameY = sy + math.sin(flamePhase + i * 1.5) * r * 0.12
        local flameR = r * (0.12 - frac * 0.02)
        local flameAlpha = 0.45 - frac * 0.10
        nvgBeginPath(vg)
        nvgCircle(vg, flameX, flameY, flameR)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b,
            flameAlpha))
        nvgFill(vg)
    end
    -- 焰尾连线（飞白朱砂弧）
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.45, sy)
    nvgBezierTo(vg,
        sx - r * 0.7, sy + math.sin(flamePhase) * r * 0.1,
        sx - r * 0.9, sy - math.sin(flamePhase * 0.7) * r * 0.08,
        sx - r * 1.1, sy + math.sin(flamePhase * 1.3) * r * 0.06)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.30))
    nvgStroke(vg)

    -- 眼睛：火红光点
    local eyeX = sx + r * 0.2
    local eyeY = sy - r * 0.25
    nvgBeginPath(vg)
    nvgCircle(vg, eyeX, eyeY, r * 0.055)
    nvgFillColor(vg, nvgRGBAf(
        InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.85))
    nvgFill(vg)

    -- 墨气（浓重的黑色气场）
    BrushStrokes.inkWash(vg, sx, sy, r * 0.25, r * 0.7,
        ink, 0.10)

    nvgRestore(vg)
end

return BeastRenderer
