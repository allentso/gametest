# 《山海异闻录·寻光》贴图生产规划文档

> 版本：1.0 ｜ 更新日期：2026-04-10
> 范围：异兽贴图（24种 × 3变体）+ 资源贴图（10种）+ 优先级分析

---

## 一、总体分析与优先级

### 1.1 当前缺口统计

| 类别 | 总数 | 已有贴图 | 缺口 | 备注 |
|------|------|---------|------|------|
| 异兽·正常态 | 24 | 0 | **24** | 全部为程序矢量 |
| 异兽·异文变体 | 24 | 0 | **24** | 翡翠纹线叠加层 |
| 异兽·玄采变体 | 24 | 0 | **24** | 靛蓝光环叠加层 |
| 资源图标 | 10 | 8 | **2** | 不死草、灵印缺失 |
| 线索图标 | 4 | 4 | 0 | 完备 |
| 撤离法阵 | 1 | 1 | 0 | 完备 |
| 技能图标 | 6 | 0 | 6 | 文字占位，P3 |
| 流派图标 | 4 | 0 | 4 | 文字占位，P3 |
| 锻造物品 | 10 | 0 | 10 | 文字占位，P3 |

**核心缺口：72 张异兽贴图（24 × 3变体）+ 2 张资源图标**

### 1.2 分批生产建议

| 批次 | 内容 | 数量 | 理由 |
|------|------|------|------|
| **P0·立即** | 资源图标缺失修补 | 2 张 | 不死草无任何渲染，影响游戏内显示 |
| **P1·优先** | SSR 六灵正常态 | 6 张 | 最高品质，玩家最期待遭遇 |
| **P2·核心** | SR 十异正常态 | 10 张 | 主要游戏内容 |
| **P3·补全** | R 八兆正常态 | 8 张 | 基础内容完善 |
| **P4·变体** | 全异兽·异文变体 | 24 张 | 在正常态基础上叠加纹理 |
| **P5·变体** | 全异兽·玄采变体 | 24 张 | 在正常态基础上叠加光效 |
| **P6·可选** | 技能/流派/锻造图标 | 20 张 | 改善 PrepareScreen 体验 |

---

## 二、通用负面提示词（所有贴图共用）

```
(3D render:1.3), (photorealistic:1.3), glowing lights, neon colors, 
heavy shadows, bevel and emboss, glossy, metallic, modern UI, 
gradient mesh, messy background, colorful, cluttered, thick painting, 
oil painting, western style, anime, manga, cartoon, cel-shading,
digital painting, concept art, illustration style
```

---

## 三、变体叠加层说明

变体**不是独立贴图**，而是在正常态基础上叠加的覆盖层。生成逻辑：

| 变体 | 叠加描述 | Prompt 追加词 |
|------|---------|--------------|
| `normal` 正常态 | 基础白描 | ——（见各异兽独立 Prompt） |
| `yiwen` 异文 | 翡翠绿旋转纹线覆盖 | `with subtle jade green rotating calligraphy pattern overlay, ink seal texture, emerald tones, semi-transparent` |
| `xuancai` 玄采 | 靛蓝光环 + 环绕粒子 | `with indigo blue luminous halo surrounding the figure, floating ink particle dots in deep blue, ethereal glow` |
| `xuancai_yiwen` | 两者组合 | 叠加上述两条描述 |

> **实现建议**：变体叠加层可以生成为独立透明 PNG（仅含纹理/光效，无主体），在渲染时叠加在 `normal` 贴图上，减少生产数量为 24（正常）+ 2（叠加层模板）= 26 张核心资源。

---

## 四、资源图标 Prompt（P0 优先）

**规格**：128×128px，透明背景 PNG，平面图标风格

**通用基础 Prompt 模板（资源类）**：
```
Game icon design, [ITEM], flat 2D vector style, 
traditional Chinese calligraphy brushwork. 
Visuals: Hand-drawn irregular edges, ink splatter details, organic shapes. 
Color Palette: Cinnabar red, Jade green, and Ink black only. 
Background: Pure white background. 
Style: Minimalist, seal script aesthetic, high quality line art, 
no gradients, no shadows.
```

---

### R-09 不死草 `busicao` ⚠️ P0 紧急

**来源描述**：极稀有的复活灵草，仅生于瘴气深处，通体翠绿发光。

```
Game icon design, a single miraculous herb with three jade-green leaves 
sprouting from twisted dark root, glowing with faint spiritual light, 
flat 2D vector style, traditional Chinese calligraphy brushwork. 
Visuals: Hand-drawn irregular leaf edges, ink splatter at root tips, 
fine vein lines on leaves, tiny floating light particles above leaves. 
Color Palette: Deep jade green leaves, cinnabar red veins, ink black outline. 
Background: Pure white background. 
Style: Minimalist, Shanhaijing botanical illustration aesthetic, 
high quality line art, no gradients, no shadows.
```

---

### R-10 灵印 `lingyin` · P2

**来源描述**：荣耀货币，朱砂印鉴，仅作 UI 展示用。

```
Game icon design, a square jade seal stamp with cinnabar red ink impression, 
ancient Chinese seal script character "印" carved in relief, 
flat 2D vector style, traditional Chinese calligraphy brushwork. 
Visuals: Hand-carved stone texture on seal body, ink bleed effect 
at stamp impression edges, organic irregular ink spread. 
Color Palette: Cinnabar red stamp ink, jade green stone, ink black outline. 
Background: Pure white background. 
Style: Minimalist, seal script (Zhuanshu) aesthetic, 
high quality line art, no gradients, no shadows.
```

---

### 现有 8 种资源参考 Prompt（备份/重制用）

<details>
<summary>展开查看 R-01 至 R-08</summary>

**R-01 灵石 `lingshi`**
```
Game icon design, a hexagonal jade crystal cluster, 
translucent emerald green with natural fracture lines, 
flat 2D vector style, traditional Chinese calligraphy brushwork.
Color Palette: Jade green, ink black outline, white highlight.
Background: Pure white. Style: Minimalist seal script aesthetic.
```

**R-02 天晶 `tianjing`**
```
Game icon design, a golden rhombus crystal with four-pointed star gleam, 
divine golden mineral, flat 2D vector style.
Color Palette: Gold, cinnabar accent, ink black outline.
Background: Pure white. Style: Minimalist, no gradients.
```

**R-03 兽魂 `shouhun`**
```
Game icon design, a ghostly blue flame in Bezier curve shape, 
spiritual beast essence, wispy and organic, flat 2D vector style.
Color Palette: Azure blue, deep indigo, ink black outline.
Background: Pure white. Style: Minimalist calligraphy brushwork.
```

**R-04 追迹灰 `traceAsh`**
```
Game icon design, a small heap of grey ash with three floating ash particles, 
tracking incense residue, flat 2D vector style.
Color Palette: Ash grey, ink black outline, faint cinnabar accent.
Background: Pure white. Style: Minimalist, organic irregular shape.
```

**R-05 镇灵砂 `mirrorSand`**
```
Game icon design, an azure rhombus crystal cluster, 
spirit-suppressing mineral sand, flat 2D vector style.
Color Palette: Azure blue, ink black outline.
Background: Pure white. Style: Minimalist, no gradients.
```

**R-06 归魂符 `soulCharm`**
```
Game icon design, a small rectangular yellow talisman paper 
with cinnabar red seal script characters, folded slightly at corner, 
flat 2D vector style.
Color Palette: Pale yellow paper, cinnabar red ink, ink black edge.
Background: Pure white. Style: Minimalist, hand-drawn irregular edges.
```

**R-07 兽目珠 `beastEye`**
```
Game icon design, a glass orb containing a beast's vertical-slit pupil, 
mystical seeing eye bead, flat 2D vector style.
Color Palette: Amber gold iris, ink black pupil, jade green orb.
Background: Pure white. Style: Minimalist, no gradients.
```

**R-08 封印回响 `sealEcho`**
```
Game icon design, a circular seal talisman with radiating sound wave rings, 
spiritual echo resonance symbol, flat 2D vector style.
Color Palette: Cinnabar red seal, ink black waves, white space.
Background: Pure white. Style: Minimalist, calligraphy brushwork.
```

</details>

---

## 五、SSR 六灵 异兽 Prompt（P1 优先）

**规格**：128×128px，纯白背景 PNG，俯视角游戏精灵

**通用基础 Prompt 模板（异兽类）**：
```
Minimalist Chinese Ink Wash painting, [SUBJECT], top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on [TEXTURE AREA]. 
Colors: Pure black ink lines, [ACCENT COLOR] subtle ink wash halo. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### SSR-001 烛龙

**原典**：人面蛇身，通体赤红，竖瞳，掌昼夜。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a colossal divine dragon with human face and serpent body, 
seen from directly above, coiled in a spiral, 
vertical dragon pupils blazing with subtle red ink, 
human face rendered with fine Baimiao line detail at snake head position,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on serpent scales. 
Colors: Pure black ink lines, cinnabar red subtle ink wash halo along body. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：在 normal 基础追加
```
with subtle jade green rotating calligraphy seal-script pattern overlay 
along the serpent body, emerald tones, semi-transparent ink texture
```

**玄采叠加层 `xuancai`**：在 normal 基础追加
```
with deep indigo luminous halo surrounding the coiled body, 
floating cinnabar ink particle dots radiating outward, ethereal night glow
```

---

### SSR-002 应龙

**原典**：有翼神龙，杀蚩尤与夸父，助大禹治水。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a mighty winged dragon seen from directly above, 
both wings spread wide filling the frame, 
dragon scales rendered with fine Cun-texture (rock wrinkle) strokes, 
powerful claws visible at wingtips, 
tail coiling at bottom edge of frame,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on wing membranes. 
Colors: Pure black ink lines, golden amber subtle ink wash halo on wings. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：
```
with jade green ancient dragon seal-script rune pattern overlay 
on wing membranes, emerald tones, semi-transparent
```

**玄采叠加层 `xuancai`**：
```
with golden lightning bolt halo radiating from wing edges, 
deep indigo atmospheric glow, floating thunder-spark ink particles
```

---

### SSR-003 凤凰

**原典**：形如鸡，五采而文，首文曰德，自歌自舞，见则天下安宁。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a divine phoenix bird seen from directly above in mid-dance pose, 
five-colored feathers suggested by layered fine line strokes 
(not actual color, only varied ink density), 
long tail feathers spread in circular fan pattern, 
crest feathers visible at top,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on tail plumes. 
Colors: Pure black ink lines, five-element color ink wash: 
faint red at crest, faint gold at wings, faint jade at breast, 
subtle ink washes only. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：
```
with jade green five-virtue calligraphy characters 
(德义礼仁信) floating around the figure, 
rotating slowly, semi-transparent seal script style
```

**玄采叠加层 `xuancai`**：
```
with warm golden five-color luminous halo radiating from the body, 
tiny five-colored ink petal particles floating upward, 
celestial aurora glow effect
```

---

### SSR-004 白泽

**原典**：白毛，龙角（或羊角），能言，达于万物之情。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a divine white beast resembling a large dog with dragon horns, 
seen from directly above, 
horns curling upward at top of frame, 
thick pure white fur suggested by sparse fine Baimiao lines 
(mostly white space), 
intelligent all-knowing eyes rendered with precision,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on fur outline. 
Colors: Pure black ink lines (minimal, 70% white space), 
warm golden white subtle ink wash halo. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：
```
with ancient Chinese script characters floating around the figure, 
referencing the ten-thousand spirits catalogue, 
jade green semi-transparent calligraphy overlay
```

**玄采叠加层 `xuancai`**：
```
with brilliant white-gold omniscient halo, 
floating ancient text particle dots in golden ink radiating outward, 
divine wisdom glow
```

---

### SSR-005 白虎

**原典**：白色猛虎，主西方，主肃杀，王者有德时见。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a pure white tiger seen from directly above in prowling stance, 
"王" character stripe pattern on forehead rendered in fine ink lines, 
powerful muscular body with minimal fur detail lines, 
golden claw prints visible at paw positions,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on fur body. 
Colors: Pure black ink lines, golden accent on claws and forehead mark, 
subtle white fur rendering. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：
```
with jade green military authority seal-script rune pattern overlay, 
ancient war talisman texture, emerald semi-transparent calligraphy
```

**玄采叠加层 `xuancai`**：
```
with silver-white fierce warrior halo, 
gold dust ink particles scattering from pawprints, 
western metal element divine glow
```

---

### SSR-006 麒麟

**原典**：鹿身、牛尾、马蹄、独角，四灵之一，仁兽，不践生虫。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a noble qilin seen from directly above in gentle walking pose, 
deer body with single straight horn at head top, 
horse hooves, ox-like tail, 
body radiating very faint golden light suggested by sparse line work, 
stepping around (not on) a tiny flower detail,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on flank and mane. 
Colors: Pure black ink lines, warm jade gold subtle ink wash halo. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文叠加层 `yiwen`**：
```
with jade green four-auspicious-spirits (龙凤龟麟) calligraphy 
rotating around figure, four-ling seal script overlay, 
emerald semi-transparent
```

**玄采叠加层 `xuancai`**：
```
with warm gold auspicious halo, 
floating golden petal-shaped ink particles rising upward, 
benevolent divine light, holy emperor glow
```

---

## 六、SR 十异 异兽 Prompt（P2 优先）

---

### SR-007 饕餮（原型：狍鸮）

**原典**：羊身人面，目在腋下，虎齿人爪，音如婴儿，食人。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a grotesque beast with sheep body and human face embedded in chest, 
two additional eyes at armpit positions (six eyes total visible from above), 
tiger fangs protruding from human face, human-like clawed hands, 
seen from directly above showing all body elements,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on fleece body. 
Colors: Pure black ink lines, deep dark ink wash creating ominous shadows 
at eye positions, subtle dark halo. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`deep dark seal script "贪" character overlay on chest, ominous ancient warning text, cinnabar red semi-transparent`
- 玄采：`with consuming dark void halo, ink being pulled inward like a black hole vortex, darkness particle absorption effect`

---

### SR-008 穷奇

**原典**：如牛，猬毛，音如嗥狗，食人。后世多作有翼版本。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a bull-shaped beast covered entirely in dense outward-pointing quill spines, 
each spine rendered as a fine radiating ink line, 
thick muscular ox body bristling with hedgehog-like quills in all directions, 
massive jaw open in howl position, seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects at quill tips. 
Colors: Pure black ink lines, dark grey-black ink wash on body mass, 
white quill highlights. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green rebellious spirit rune pattern between quills, ancient heretic seal script, emerald semi-transparent`
- 玄采：`with dark storm halo, grey wind vortex particles spinning at quill tips, chaotic energy effect`

---

### SR-009 梼杌

**原典**：顽凶难化，不可教训，四凶之一，虎犬混合，极难驯服。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a massive shaggy beast combining tiger and hound features, 
enormous matted fur body (suggesting stubborn immovable mass), 
face obscured by tangled fur strands, 
four wide-spread powerful legs planting firmly, 
seen from directly above showing its territory-claiming bulk,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on matted fur tangles. 
Colors: Pure black ink lines, deep charcoal grey ink wash on fur mass, 
minimal highlights. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`ancient incorrigible spirit seal characters embedded in fur texture, inescapable curse script overlay, cinnabar red semi-transparent`
- 玄采：`with dark immovable force halo, stubborn stone-grey particles radiating outward slowly, unyielding territorial glow`

---

### SR-010 混沌（帝江）

**原典**：黄囊，赤如丹火，六足四翼，浑敦无面目，识歌舞。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a perfectly round blob-shaped deity with no facial features whatsoever, 
six small legs protruding from bottom, four wing-stubs at sides, 
body like a swollen yellow sack, seen from directly above, 
the complete absence of face is the visual focal point 
(empty smooth oval where face should be),
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on round body outline. 
Colors: Pure black ink lines, warm amber-yellow ink wash on body, 
cinnabar red wing accent. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green pre-chaos primordial pattern overlay (無 / 混 characters), formless origin script, emerald semi-transparent`
- 玄采：`with cosmic void halo, no-face spiritual particles floating in all directions, primordial chaos energy glow`

---

### SR-011 九婴

**原典**：九首蛇龙，大水火之怪，为人害。被羿所杀。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a nine-headed serpent dragon seen from directly above, 
central body with nine necks radiating outward like compass directions, 
four heads with water droplet details (water attribute), 
four heads with flame spike details (fire attribute), 
one central golden main head larger than others, 
necks interweaving in serpentine patterns,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on scales between heads. 
Colors: Pure black ink lines, alternating azure blue and cinnabar red 
subtle ink wash on different neck groups. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green nine-head talisman ward script overlay between necks, ancient binding seal pattern, emerald semi-transparent`
- 玄采：`with dual-element water-fire halo (azure and cinnabar swirling), disaster energy particles spiraling from each head`

---

### SR-012 猰貐

**原典**：蛇身人面，贰负臣所杀，死而复生，化为食人怪。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a serpent-bodied creature with contorted human face at head, 
body partially coiled with evidence of fatal wounds 
(fine ink tear-line details suggesting previous death), 
human face expression showing unnatural revival snarl, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on scales and wound areas. 
Colors: Pure black ink lines, grey-ash ink wash on body 
(suggesting undeath pallor), faint cinnabar red at wound marks. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green undying revival seal script overlay, immortal curse characters wrapping body, emerald semi-transparent`
- 玄采：`with undead grey-green revival halo, death and rebirth cycle particles, necrotic spiritual glow`

---

### SR-013 毕方

**原典**：如鹤，一足，赤文青质而白喙，见则其邑有讹火。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a crane-shaped fire omen bird standing on ONE leg only, 
azure-tinted feather body with red cinnabar stripe pattern, 
pure white beak pointing forward, 
single leg rendered with emphasis as defining visual feature, 
wings slightly raised in omen stance, seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on wing plumage. 
Colors: Pure black ink lines, azure blue body wash, 
cinnabar red stripe accents, white beak highlight. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green fire-omen warning calligraphy overlay on feathers, disaster prophecy seal script, cinnabar-tinted semi-transparent`
- 玄采：`with fire-blue omen halo, small flame-shaped ink particles rising from single foot, conflagration omen glow`

---

### SR-014 乘黄

**原典**：如狐，其背上有角，乘之寿二千岁。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a golden fox with a single curved horn growing from its back (not head), 
sleek graceful fox body, bushy tail, 
horn on back rendered prominently as unique identifier, 
in elegant mid-stride pose, seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on tail fur. 
Colors: Pure black ink lines, warm golden amber ink wash on body, 
white horn highlight. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green longevity (壽) seal script characters flowing from horn tip, ancient immortality rune overlay, emerald semi-transparent`
- 玄采：`with golden longevity halo, lifespan-extending golden light particles trailing from horn and tail, immortal auspicious glow`

---

### SR-015 文鳐鱼

**原典**：如鲤鱼，鱼身而鸟翼，苍文而白首，赤喙，常行西海，以夜飞，见则天下大穰。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a magical flying fish with bird wings instead of pectoral fins, 
carp-scaled body, pure white head, 
vivid red beak (prominent visual feature), 
azure-grey stripe pattern (苍文) on body scales, 
wings spread wide in soaring pose, seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on wing membranes. 
Colors: Pure black ink lines, azure grey scale wash, 
cinnabar red beak accent, white head highlight. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green harvest-abundance (穰) calligraphy scale-pattern overlay, bountiful year seal script, emerald semi-transparent`
- 玄采：`with moonlit night sea halo, azure night-flight particles trailing from wings, nocturnal ocean abundance glow`

---

### SR-016 九尾狐

**原典**：如狐而九尾，音如婴儿，能食人，食者不蛊。

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a fox with nine distinct tails spread in fan formation, 
elegant fox body, each tail rendered with individual fine Baimiao lines, 
tails arranged in perfect circular fan behind body, 
three tails subtly visible in R quality (suggesting more), 
six tails fully visible in SR quality, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on all nine tail tips. 
Colors: Pure black ink lines, warm fox-amber ink wash on body, 
cinnabar red flame tips on tails. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

**异文 / 玄采 叠加层**：
- 异文：`jade green illusion (幻) seal script pattern overlay on each tail, shapeshifting ward characters, emerald semi-transparent`
- 玄采：`with nine-tail enchantment halo, seductive golden-amber particles swirling from each tail, transformation spiritual glow`

---

## 七、R 八兆 异兽 Prompt（P3）

---

### R-017 帝江

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a small round blob entity with no facial features, 
six tiny legs and four small wing-stubs, 
younger and smaller than the SR Hundun version, 
cheerfully round body in dancing pose suggested by angled limbs, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness. 
Colors: Pure black ink lines, warm amber-yellow ink wash. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-018 当康

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a small roly-poly pig with two prominent tusks curving outward, 
chubby round body with short legs, 
good-natured plump silhouette, mouth open as if calling its own name, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness. 
Colors: Pure black ink lines, light warm ink wash on plump body. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-019 狸力

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a pig-shaped beast with prominent rooster-claw talon spurs at legs, 
stocky body with distinct sharp spur detail on each leg, 
alert stance suggesting construction readiness, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on leg spurs. 
Colors: Pure black ink lines, earthy brown ink wash. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-020 旋龟

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a turtle with a bird's head (crane-like) and snake tail, 
turtle shell rendered with hexagonal Cun-texture pattern, 
long graceful bird neck at front, serpent tail coiling at rear, 
shell viewed from directly above showing pattern detail,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on snake tail. 
Colors: Pure black ink lines, jade green shell wash, azure neck wash. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-021 并封

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a black pig with two heads - one at front and one at rear, 
both heads identical and fully formed, 
four legs in the middle, body completely symmetrical front-to-back, 
deep black body rendering creating uncanny silhouette, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness. 
Colors: Pure black ink lines, deep black ink wash on body 
(high contrast minimal white). 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-022 何罗鱼

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
one fish head with ten separate bodies trailing behind it in a fan spread, 
each body a complete fish form, all connected to single central head, 
bodies spreading outward like fingers from a palm, 
seen from directly above showing the radial arrangement,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness. 
Colors: Pure black ink lines, azure blue ink wash on bodies. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-023 化蛇

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
a serpent-crawling creature with human face, jackal body, and bird wings 
(wings folded flat against back), 
human face facing upward when viewed from above, 
serpentine body movement suggested by S-curve posture, 
wings visible as folded shapes on either side,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness. 
Colors: Pure black ink lines, azure ink wash on wings, 
warm skin tone line suggestion on human face. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

### R-024 蜚

**正常态 `normal`**
```
Minimalist Chinese Ink Wash painting, 
an ox-shaped beast with pure white head and single eye (centered), 
serpent tail coiling behind, 
white head is the most distinctive visual feature (stark against body), 
single Cyclops eye rendered with precision, 
ox body with plague-carrier aura suggested by slight withering of ground lines, 
seen from directly above,
top-down view for game sprite, 
fine line art (Baimiao technique), varied brush stroke thickness, 
"flying white" dry brush effects on serpent tail. 
Colors: Pure black ink lines, white head (negative space), 
single dark eye, grey body wash. 
Background: Solid pure white background (no texture). 
Style: High contrast, traditional Zen aesthetic, 
Shanhaijing illustration style, clean edges, no shading, no 3D rendering.
```

---

## 八、文件命名与注册规范

### 8.1 命名规则

```
<类型前缀>_<名称>_<日期时间戳>.png

异兽·正常态：  beast_zhulongNormal_20260410XXXXXX.png
异兽·异文：    beast_zhulongYiwen_20260410XXXXXX.png
异兽·玄采：    beast_zhulongXuancai_20260410XXXXXX.png
资源图标：     item_busicao_20260410XXXXXX.png
```

### 8.2 IMAGE_PATHS 注册模板

```lua
-- 异兽贴图（在 InkRenderer.lua 的 IMAGE_PATHS 表中添加）
IMAGE_PATHS = {
  -- 资源图标
  lingshi    = "image/items/item_lingshi_20260408114828.png",
  busicao    = "image/items/item_busicao_XXXXXXXXX.png",   -- P0 新增
  lingyin    = "image/items/item_lingyin_XXXXXXXXX.png",   -- P2 新增

  -- 异兽·正常态（24种）
  beast_zhulongNormal    = "image/beasts/beast_zhulongNormal_XXXXXXXXX.png",
  beast_yinglongNormal   = "image/beasts/beast_yinglongNormal_XXXXXXXXX.png",
  -- ... 以此类推

  -- 异兽·异文变体（24种）
  beast_zhulongYiwen     = "image/beasts/beast_zhulongYiwen_XXXXXXXXX.png",
  -- ...

  -- 异兽·玄采变体（24种）
  beast_zhulongXuancai   = "image/beasts/beast_zhulongXuancai_XXXXXXXXX.png",
  -- ...
}
```

### 8.3 存放目录结构

```
assets/image/
├── items/          ← 资源图标（现有8张 + 新增2张）
├── clues/          ← 线索图标（现有4张，完备）
├── evacuation/     ← 撤离法阵（现有1张，完备）
└── beasts/         ← 异兽贴图（新建目录）
    ├── ssr/        ← 六灵（6×3=18张）
    ├── sr/         ← 十异（10×3=30张）
    └── r/          ← 八兆（8×3=24张）
```

---

## 九、生产排期参考

| 阶段 | 内容 | 张数 | 参考工作量 |
|------|------|------|-----------|
| P0 本周 | 不死草图标 | 1 | 30分钟 |
| P1 第1周 | SSR 六灵正常态 | 6 | 6×1小时 |
| P2 第2周 | SR 十异正常态 | 10 | 10×45分钟 |
| P3 第3周 | R 八兆正常态 | 8 | 8×30分钟 |
| P4 第4周 | 全异兽异文叠加层 | 24 | 批量生成 |
| P5 第5周 | 全异兽玄采叠加层 | 24 | 批量生成 |
| P6 按需 | 技能/流派/锻造图标 | 20 | 视优先级 |

**总计核心贴图**：2（资源）+ 72（异兽）= **74 张**

---

*文档版本: 1.0*
*维护说明: 每完成一批贴图，在 texture-index.md 中同步更新对应行状态*
