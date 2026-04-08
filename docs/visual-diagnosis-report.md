# 视觉诊断报告：渲染实现 vs ui.md 规范

> **项目**：山海异闻录：寻光  
> **诊断日期**：2026-04-08  
> **诊断范围**：ExploreScreen 六层渲染体系  
> **对照文档**：`docs/ui.md` v1.0  

---

## 一、总体评估

| 维度 | 规范要求 | 当前状态 | 严重度 |
|------|---------|---------|--------|
| 瓦片连续性 | 连续水墨画卷，无格线 | 孤立墨晕方块，强烈网格感 | **P0 致命** |
| 实体具象化 | 白描具象形态 | 6/10 种异兽为默认椭圆 + 眼点 | **P0 致命** |
| 迷雾层级 | 世界级径向渐变遮罩 | 屏幕级暗角滤镜 | **P1 严重** |
| 底栏风格 | 水墨印章风 | 现代圆角卡片 + 扁平圆点 | **P2 中等** |
| 笔触品质 | 飞白断笔、粗细变化 | 已实现但覆盖率不足 | **P2 中等** |
| 色彩规范 | InkPalette 唯一色源 | 符合 | ✅ 通过 |
| 六层架构 | Paper→Tile→Entity→Fog→HUD→Modal | 符合 | ✅ 通过 |

**综合判定**：渲染管线架构正确，色彩体系达标，但**视觉输出距离"水墨画卷"的目标存在质的差距**。核心问题是瓦片渲染产出的是"格子阵列"而非"连续画面"，实体渲染产出的是"抽象符号"而非"具象白描"。

---

## 二、P0 致命问题详解

### 2.1 瓦片网格感（"消除游戏"观感）

#### 规范要求（ui.md §4.4.1-4.4.2）

> "地图是一幅连续的水墨画卷，不是方格拼图。"
>
> 1. 先用 `nvgRadialGradient` 从瓦片中心向外画底色晕染（alpha ≤ 0.35），**渐变到完全透明**
> 2. 再叠加笔触细节
> 3. 相邻瓦片的晕染**自然重叠**，形成连续的有机画面
> 4. **绝不画任何矩形边框**

#### 当前实现分析

**文件**：`scripts/render/InkTileRenderer.lua`

**草地（占地图 ~50%）**：

```lua
-- InkTileRenderer.drawGrass() 第63-65行
BrushStrokes.inkWash(vg, sx, sy, ppu * 0.05, ppu * 0.55, c, 0.06 * alphaScale)
```

- 内径 `ppu * 0.05` → 几乎是一个点
- 外径 `ppu * 0.55` → 仅略大于半个格子（一个格子=1.0×ppu）
- **问题**：外径不足以覆盖到邻格中心，相邻瓦片的晕染之间存在明显**间隙**
- **alpha 0.06**：极度微弱，jade 色几乎不可见，草地瓦片在视觉上约等于空白宣纸

**草笔触**受 `Config.TILE_DETAIL` 控制：

```lua
-- InkTileRenderer.drawGrass() 第68行
if tile.grassStrokes and Config.TILE_DETAIL then
```

- `Config.TILE_DETAIL` 初始值 `true`（Config.lua 第6行），但**自动降级系统**可能在运行时将其设为 `false`：

```lua
-- Config.autoAdjust() 第34行
Config.TILE_DETAIL = Config.QUALITY >= 1
```

- 当帧率低于 40fps 时 QUALITY 降级为 0，`TILE_DETAIL = false`，草地退化为**纯墨晕圆点**
- 即便 TILE_DETAIL 为 true，每格仅 2-3 笔草，且兰草笔触的偏移范围（`0.6×ppu`）不超出格子范围

**岩石**：

```lua
-- InkTileRenderer.drawRock()
BrushStrokes.inkWash(vg, sx, sy, ppu * 0.08, ppu * 0.5, ...)  -- 外径 0.5 ppu
BrushStrokes.cunTexture(vg, sx, sy, ppu * 0.4, ...)            -- 散布范围 0.4 ppu
```

- 皴法笔触仅覆盖格内 80% 区域，与邻格之间有明显空白

**所有地形通病**：

| 地形 | 底色晕染外径 | 覆盖率 | 问题 |
|------|------------|--------|------|
| grass | 0.55 ppu | 55% | 相邻格间隙 ~45% |
| rock | 0.50 ppu | 50% | 明显分离 |
| water | 0.55 ppu | 55% | 水纹仅覆盖格内 |
| path | 0.50 ppu | 50% | 赭石晕变成小圆点 |
| bamboo | 0.50 ppu | 50% | 竹竿不跨格 |
| danger | 0.55 ppu | 55% | 瘴气晕变成小圆点 |

**要达到"连续画面"效果，底色晕染外径至少需要 `0.75~0.90 ppu`**，使相邻瓦片的渐变区域有 50%+ 重叠。

#### 根因总结

1. **晕染半径太小**：所有瓦片的 `inkWash` 外径仅 0.50-0.55 ppu，无法与邻格重叠
2. **底色 alpha 太低**：草地 0.06、小径 0.10，在宣纸上几乎不可见
3. **笔触不跨格**：草/竹/水纹的偏移量都严格限制在格子内部
4. **格子阵列的本质**：20×30 个独立的小圆点排列成网格，形成强烈的"方格拼图"视觉

---

### 2.2 实体不可辨识（抽象符号 vs 具象白描）

#### 规范要求（ui.md §4.4.4）

> "具象化水墨，非图标" —— 用水墨笔触组合成具象化的白描形态

10 种异兽中，规范要求每种都有独特的"水墨画法形态"。

#### 当前实现分析

**文件**：`scripts/render/BeastRenderer.lua`

| 异兽 ID | 名称 | 当前实现 | 规范差距 |
|---------|------|---------|---------|
| 001 | 玄狐 | 卧形椭圆 + 三角耳 + 贝塞尔尾 | **可接受**，有辨识度 |
| 002 | 噬天蟒 | S 形贝塞尔 + 圆头 | **可接受**，蛇形明显 |
| 003 | 雷翼鹏 | 椭圆身 + 两条弧线翼 | **勉强**，翼过于简化 |
| 004 | 白泽 | 圆角矩形 + 三角角 | **勉强**，像带尖的方块 |
| 005 | 石灵 | cunTexture 散点 + 中心圆 | **差**，像岩石瓦片而非生物 |
| 006 | 水蛟 | 贝塞尔弧 + 水花晕 | **可接受** |
| 007-010 | 4 种异兽 | **全部使用 drawDefaultShape** | **完全不达标** |

**drawDefaultShape（默认形态）的问题**：

```lua
function BeastRenderer.drawDefaultShape(vg, sx, sy, r, t, beast)
    -- 主体：墨色椭圆
    nvgEllipse(vg, sx, sy, r * 0.85, r * 0.65)
    -- 描边轮廓
    nvgEllipse(vg, sx, sy, r * 0.9, r * 0.7)
    -- 眼睛：朝向方向的小白点
    nvgCircle(vg, eyeX, eyeY, r * 0.08)
end
```

- 一个填充椭圆 + 一个描边椭圆 + 一个白点 = **"表情包脸"**
- 007（青鸾）、008（岩甲龟）、009（幻蝶）、010（冰魄狼）全部渲染为完全相同的墨色椭圆
- 玩家无法区分不同异兽，丧失了"百鬼图鉴"的收集动力

**bodySize 问题**：

```lua
local r = (beast.bodySize or 0.4) * ppu
```

- 大部分异兽没有设置 `bodySize`，默认 0.4 格 → 在屏幕上仅约 16px 大小，**太小了**
- 品质光晕（SR/SSR）的脉冲半径是 `r * 2.0`，在 16px 主体上产生 32px 光晕，比例还行但绝对尺寸太小

#### 根因总结

1. **40% 异兽无专属形态**：007-010 四种使用通用椭圆，无任何辨识度
2. **已有形态过于简化**：最复杂的"玄狐"也仅 3 个图元（椭圆+三角+弧线），缺乏水墨画的"笔触层次感"
3. **整体尺寸偏小**：默认 0.4 格 → 屏幕上 ~16px，在手机上几乎看不清细节

---

## 三、P1 严重问题详解

### 3.1 迷雾渲染：屏幕级暗角 vs 世界级遮罩

#### 规范要求（ui.md §4.4.3）

> "以玩家屏幕坐标为中心，视野半径×PPU为内径，外径比内径大 15-20%，从 alpha 0 渐变到 alpha 0.9。"
>
> DARK 区域：保持宣纸底色上叠加的**纯墨色遮罩**

迷雾应该是一个**覆盖在地图上的世界级遮罩**：以玩家为中心的视野圆清晰可见，圆外渐变到浓墨遮盖。

#### 当前实现分析

**文件**：`scripts/render/InkRenderer.lua` → `drawFog()`

```lua
-- InkRenderer.drawFog()
local innerR = visionPx * 0.92
local outerR = visionPx * 1.15

nvgBeginPath(vg)
nvgRect(vg, 0, 0, logW, logH)  -- 全屏矩形
local paint = nvgRadialGradient(vg, playerSX, playerSY, innerR, outerR,
    nvgRGBAf(0, 0, 0, 0),
    nvgRGBAf(InkPalette.inkDark.r, InkPalette.inkDark.g, InkPalette.inkDark.b, 0.88))
nvgFillPaint(vg, paint)
nvgFill(vg)
```

**技术上是正确的**——使用了径向渐变，以玩家为中心。但存在以下问题：

| 问题 | 详情 |
|------|------|
| 外径 alpha 仅 0.88 | 规范要求 0.9；差距微小但使远处区域不够"黑" |
| 渐变过渡带太窄 | `outerR / innerR = 1.25`，规范要求 15-20% 差，当前实现实际只有 ~25%，尚可接受 |
| DARK 区域仍可见瓦片 | `ExploreScreen.renderTiles()` 中仅跳过 `DARK` 状态不绘制瓦片（正确），但迷雾遮罩的 0.88 alpha 不足以完全遮盖宣纸底色差异 |
| 缺少世界级迷雾质感 | 迷雾仅是一层均匀渐变，没有墨色浓淡变化、没有模拟"墨水渗透"的有机边缘 |

**用户感知**："像是给画面套了个圆形 vignette 滤镜"——这个评价基本准确，因为当前迷雾确实只是一个径向渐变，缺乏水墨质感。

**氛围层（drawAtmosphere）的问题**：

```lua
-- InkRenderer.drawAtmosphere()
-- 顶部 8% 线性渐变 + 底部 8% 线性渐变
```

- 这是**固定的屏幕装饰**，不随玩家/相机移动
- 本质上是一个 UI 层暗角效果，不是世界级的氛围

#### 根因总结

1. **迷雾遮罩过于均匀**：纯数学径向渐变，没有水墨质感的浓淡变化
2. **氛围效果是屏幕级的**：固定在屏幕四角/边缘，与玩家位置无关
3. **缺少"墨气弥漫"的世界感**：应该在视野边缘有不规则的墨色渗透、云雾状的随机纹理

---

## 四、P2 中等问题详解

### 4.1 底栏：现代扁平风 vs 水墨卷轴风

#### 规范要求（ui.md §4.5）

> 背景：paper 色 78% 不透明度 + inkWash 35% 描边, 圆角 8px
> 灵契印章：14px 圆角方块, cinnabar 15%填充+65%描边

#### 当前实现

**文件**：`scripts/screens/ExploreScreen.lua` → `renderBottomBar()`

```lua
-- 背景
nvgRoundedRect(vg, barX, barY, barW, barH, 8)
nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.78))
nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35))
```

**规范数值层面已达标**。但用户反馈"现代扁平风"，原因是：

| 对比项 | 当前效果 | 水墨感改进方向 |
|--------|---------|---------------|
| 矩形边框 | NanoVG `nvgRoundedRect` = 完美圆角矩形 | 应使用 `BrushStrokes.inkRect`（飞白描边） |
| 线索进度 | 5 个标准圆 `nvgCircle` = 扁平圆点 | 可改为墨点（`inkDotStable`），增加不规则感 |
| 道具显示 | 小圆点 + ×N 文字 | 缺少手写体质感，颜色分布均匀没有"印章"意味 |
| 灵契印章 | `nvgRoundedRect` + 文字 | 方向正确，但边框过于规整 |

#### 根因

底栏的数值参数（颜色、alpha、位置）完全符合规范，但**绘制方法使用了标准几何图元**（`nvgRoundedRect`、`nvgCircle`），而非 BrushStrokes 工具库中的水墨笔触原语。这导致底栏在视觉上呈现"设计软件里画的 UI 稿"而非"水墨画上的题跋"。

### 4.2 摇杆绘制

**文件**：`scripts/systems/VirtualJoystick.lua` → `draw()`

```lua
nvgCircle(vg, cx, cy, r)     -- 完美圆 = 现代UI
nvgCircle(vg, knobX, knobY, 16)  -- 完美圆 = 现代UI
```

摇杆使用标准圆形绘制。在水墨主题下应使用 `inkWash` 底盘 + `inkDotStable` 手柄，产生不规则的墨晕效果。

---

## 五、已达标项

| 项目 | 状态 | 说明 |
|------|------|------|
| InkPalette 色彩体系 | ✅ | 宣纸双色、墨色五阶、五色点缀全部正确 |
| 六层渲染架构 | ✅ | Paper→Tile→Entity→Fog→HUD→Controls 顺序正确 |
| 玩家斗笠形态 | ✅ | 浓墨实心圆 + 描边圆 + 顶部墨点 + 方向朱砂线 + 脉动呼吸 |
| 线索三种形态 | ✅ | 足迹/元素残响/巢穴各有独立画法，符合规范 |
| 撤离点渲染 | ✅ | 3 层 jade 同心环 + gold 中心点 + 进度弧 |
| 品质光晕 | ✅ | R 无光晕 / SR 单层 azure / SSR 三层 gold + 粒子旋转 |
| 异兽状态特效 | ✅ | 警觉"!" / 逃跑速度线 / 偷袭"袭"字闪现 |
| 宣纸纤维纹理 | ✅ | 程序化生成，受 `INK_FIBERS` 控制 |
| Toast 卷轴样式 | ✅ | 双层墨框 + 两端圆柱装饰 |
| 行迹墨尘 | ✅ | 移动时生成递减 alpha 的淡墨点 |

---

## 六、修复优先级与路线图

### Phase 1：瓦片连续性修复（P0）

**目标**：消除网格感，让地图看起来像一幅连续的水墨画

**改动文件**：`InkTileRenderer.lua`

| 改动项 | 当前值 | 目标值 | 原理 |
|--------|--------|--------|------|
| 底色晕染外径 | 0.50-0.55 ppu | **0.75-0.90 ppu** | 使相邻瓦片晕染区域重叠 50%+ |
| 草地底色 alpha | 0.06 | **0.12-0.18** | 让色彩在宣纸上可见 |
| 岩石底色 alpha | 0.10 | **0.15-0.20** | 与规范对齐 |
| 水面底色 alpha | 0.08 | **0.12-0.18** | 让水色连片可见 |
| 草笔触偏移范围 | ±0.3-0.4 ppu | **±0.5-0.6 ppu** | 部分笔触伸入邻格 |
| 竹竿高度 | ±0.35 ppu | **±0.55 ppu** | 竹竿可跨越格线 |

**额外**：考虑在 `renderTiles` 中做两遍绘制——第一遍画所有瓦片底色晕染（大半径、低alpha），第二遍叠加笔触细节。这样底色层形成连续的色彩地基。

### Phase 2：异兽具象化（P0）

**目标**：每种异兽都有可辨识的水墨形态

**改动文件**：`BeastRenderer.lua`

| 异兽 | 当前 | 改进方向 |
|------|------|---------|
| 005 石灵 | cunTexture 散点 | 增加轮廓（不规则多边形描边），中心加"眼"意象 |
| 007 青鸾 | 默认椭圆 | 参照 003 雷翼鹏，加长尾羽弧线 + 头冠 |
| 008 岩甲龟 | 默认椭圆 | 圆角六边形壳 + 四肢短线 + 头部 |
| 009 幻蝶 | 默认椭圆 | 对称翅膀（两对贝塞尔弧线）+ 触须 |
| 010 冰魄狼 | 默认椭圆 | 侧影轮廓（头 + 尖耳 + 弓背 + 尾）|

**bodySize 调整**：默认值从 0.4 提升到 **0.55-0.65**，确保异兽在屏幕上有足够辨识度。

### Phase 3：迷雾质感增强（P1）

**目标**：迷雾从"Photoshop 滤镜"变成"墨气弥漫"

**改动文件**：`InkRenderer.lua`

1. **外径 alpha 提升**：0.88 → **0.92**
2. **在渐变过渡带叠加不规则墨点**：在 `innerR` 到 `outerR` 之间随机撒 15-20 个 `inkDotStable`，模拟墨水渗透的不规则边缘
3. **氛围层改为世界坐标**：`drawAtmosphere` 的云雾应基于相机位置偏移，而非固定在屏幕上

### Phase 4：底栏/摇杆水墨化（P2）

**改动文件**：`ExploreScreen.lua` → `renderBottomBar()`、`VirtualJoystick.lua` → `draw()`

1. 底栏边框：`nvgRoundedRect` 描边 → `BrushStrokes.inkRect`（飞白描边）
2. 线索进度：`nvgCircle` → `BrushStrokes.inkDotStable`（不规则墨点）
3. 摇杆底盘：`nvgCircle` → `BrushStrokes.inkWash`（墨晕）
4. 摇杆手柄：`nvgCircle` → `BrushStrokes.inkDotStable`（不规则墨点）

---

## 七、风险提示

### 7.1 性能降级陷阱

`Config.autoAdjust()` 在帧率低于 40fps 时自动降级：

```
QUALITY 1 → 0:  TILE_DETAIL = false, ATMOSPHERE = false
```

这会导致：
- 草地退化为纯墨晕圆点（无兰草笔触）
- 顶部/底部云雾消失

**如果增大瓦片晕染半径和异兽绘制复杂度，必须同步评估性能影响**。建议：
- 在 QUALITY=0 时使用较小的晕染半径（0.65 ppu）但仍大于当前值
- 异兽简化形态保留轮廓描边，不完全退化为椭圆

### 7.2 瓦片预计算数据

`ExploreMap.precomputeGrassStrokes()` 当前为每格生成 2-3 笔。如果扩大笔触覆盖范围并增加数量（如 4-5 笔），需要同步更新预计算逻辑。

---

## 八、附录：关键代码定位

| 问题 | 文件 | 行号/函数 |
|------|------|-----------|
| 草地晕染半径 | `render/InkTileRenderer.lua` | `drawGrass()` → `inkWash(vg, sx, sy, ppu*0.05, ppu*0.55, ...)` |
| 岩石晕染半径 | `render/InkTileRenderer.lua` | `drawRock()` → `inkWash(vg, sx, sy, ppu*0.08, ppu*0.5, ...)` |
| 水面晕染半径 | `render/InkTileRenderer.lua` | `drawWater()` → `inkWash(vg, sx, sy, ppu*0.05, ppu*0.55, ...)` |
| 草笔触开关 | `render/InkTileRenderer.lua` | `drawGrass()` → `if tile.grassStrokes and Config.TILE_DETAIL` |
| 默认异兽形态 | `render/BeastRenderer.lua` | `drawDefaultShape()` |
| 异兽尺寸 | `render/BeastRenderer.lua` | `draw()` → `(beast.bodySize or 0.4) * ppu` |
| 迷雾渐变 | `render/InkRenderer.lua` | `drawFog()` → `nvgRadialGradient(...)` |
| 氛围层（屏幕级） | `render/InkRenderer.lua` | `drawAtmosphere()` |
| 底栏绘制 | `screens/ExploreScreen.lua` | `renderBottomBar()` |
| 摇杆绘制 | `systems/VirtualJoystick.lua` | `draw()` |
| 性能降级 | `Config.lua` | `autoAdjust()` |
| 草笔触预计算 | `systems/ExploreMap.lua` | `precomputeGrassStrokes()` |
