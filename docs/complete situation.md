# 《山海异闻录：寻光》实现状态

> 最后更新: 2026-04-07

---

## 项目概况

| 项目 | 值 |
|------|-----|
| 游戏类型 | 水墨国风 · 高风险捉宠撤离 |
| 引擎 | UrhoX (Lua 5.4) |
| 渲染 | 纯 NanoVG 程序化水墨风矢量渲染 |
| 屏幕方向 | 竖屏 Portrait |
| 分辨率模式 | 模式 B（physW/dpr × physH/dpr） |
| 代码规模 | 28 个 Lua 文件，约 5,280 行 |
| 架构风格 | 模块化分层（systems / screens / data） |

---

## 文档体系

| 文档 | 职责 | 版本 |
|------|------|------|
| **game Planning.md** | 纯策划案——玩法循环、数值设计、异兽内容、经济系统 | v3.0 |
| **technical planning.md** | 纯技术方案——架构、模块接口、代码规格 | v4.0 |
| **ui.md** | 纯视觉规格——色彩体系、每个屏幕的精确渲染指令 | v2.0 |
| **complete situation.md** | 开发进度追踪（本文档） | — |

> `visual-solution-v1.md` 已删除（内容已整合至 technical planning.md 和 ui.md）

---

## 开发阶段总览

| 阶段 | 状态 | 说明 |
|------|------|------|
| Phase 1: 核心骨架 | ✅ 已完成 | 引擎初始化、地图、渲染、输入、屏幕管理 |
| Phase 2: 核心循环 | ✅ 已完成 | 计时器、异兽AI、压制/捕获/撤离、结算 |
| Phase 2.5: 竖屏迷雾重构 | 🔄 进行中 | 竖屏适配、战争迷雾、偷袭机制、视觉重塑 |
| Phase 3: 体验完善 | ⬜ 未开始 | SSR演出、图鉴、准备/合成系统、完整存档 |
| Phase 4: 留存系统 | ⬜ 未开始 | 每日任务、新手引导、更多异兽形状 |

---

## Phase 1: 核心骨架（已完成）

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| 游戏入口 | main.lua | 278 | NanoVG初始化、事件订阅、输入分发 |
| 全局配置 | Config.lua | 60 | 画质等级、地图尺寸、自动降级 |
| 调色板 | data/InkPalette.lua | 32 | 宣纸/墨色五阶/点缀色/品质色 |
| 笔触工具 | systems/BrushStrokes.lua | 109 | inkLine/inkDot/cunTexture/inkWash |
| 场景渲染 | systems/InkRenderer.lua | 303 | 宣纸底/纤维/边缘/氛围/玩家/线索/撤离点 |
| 瓦片渲染 | systems/InkTileRenderer.lua | 153 | 7种地形的水墨风格绘制 |
| 地图生成 | systems/ExploreMap.lua | 397 | 区域划分、线索/资源/撤离点生成、预计算装饰 |
| 相机 | systems/Camera.lua | 74 | 坐标转换、平滑跟随、视锥剔除 |
| 输入路由 | systems/InputRouter.lua | 60 | 分层热区注册/分发 |
| 虚拟摇杆 | systems/VirtualJoystick.lua | 101 | 竖屏左下激活区、死区、方向归一化 |
| 碰撞 | systems/CollisionSystem.lua | 77 | AABB四角检测+分轴+角落滑动 |
| 屏幕管理 | systems/ScreenManager.lua | 92 | 栈式push/pop/switch+生命周期 |
| 事件总线 | systems/EventBus.lua | 30 | on/off/emit/clear+owner批量注销 |
| 大厅 | screens/LobbyScreen.lua | 144 | 水墨风主菜单 |

---

## Phase 2: 核心循环（已完成）

| 模块 | 文件 | 行数 | 说明 |
|------|------|------|------|
| 灾变计时 | systems/Timer.lua | 82 | 4阶段(calm→warning→danger→collapse)自动递进 |
| 保底系统 | systems/PitySystem.lua | 78 | SSR硬保底80次/SR硬保底15次/渐进加成 |
| 会话状态 | systems/SessionState.lua | 167 | 灵契列表、道具背包、自动存档 |
| 异兽数据 | data/BeastData.lua | 94 | 5种异兽定义(石灵/土偶/风鸣/水蛟/冰蚕) |
| 线索追踪 | systems/TrackingSystem.lua | 107 | 3线索→SR/5线索→闪光判定→SSR |
| 异兽AI | systems/BeastAI.lua | 222 | FSM(idle/wander/alert/flee/hidden/suppress/captured) |
| 异兽渲染 | systems/BeastRenderer.lua | 450 | 5种异兽水墨画风形态+品质光环 |
| 压制QTE | systems/SuppressSystem.lua | 167 | 时机模式(R/SR)+连击模式(SSR) |
| 捕获判定 | systems/CaptureSystem.lua | 103 | 4级封灵器、自动选择最佳、消耗判定 |
| 撤离系统 | systems/EvacuationSystem.lua | 222 | 站定3秒+灵契稳定性QTE |
| 压制叠层 | screens/SuppressOverlay.lua | 286 | 模态QTE界面（双模式） |
| 灵契QTE | screens/ContractQTEOverlay.lua | 263 | 撤离时逐个处理不稳定灵契 |
| 结算 | screens/ResultScreen.lua | 305 | 灵契/丢失/用时/返回大厅 |
| 探索主屏 | screens/ExploreScreen.lua | 824 | 五层渲染+核心游戏循环集成 |

---

## Phase 2.5: 竖屏迷雾重构（进行中）

### 已完成的文档工作

- [x] 文档体系重组（策划/技术/视觉三文档分离）
- [x] game Planning.md v3.0 重写（纯策划案，无代码/色值）
- [x] technical planning.md v4.0 重写（纯技术方案，无视觉渲染代码）
- [x] ui.md v2.0 重写（纯视觉规格，含核心视觉约束禁止事项）
- [x] visual-solution-v1.md 删除（冗余内容已整合）

### 待完成的代码工作

| 优先级 | 任务 | 涉及文件 | 预估 |
|--------|------|---------|------|
| P0 | 屏幕方向改竖屏 | main.lua | 0.5h |
| P0 | 地图尺寸 32×24→20×30 | Config.lua, ExploreMap.lua | 1.5h |
| P0 | Camera 竖屏视野适配(viewH=10) | Camera.lua | 0.5h |
| P0 | 虚拟摇杆竖屏布局 | VirtualJoystick.lua | 0.5h |
| P0 | HUD 竖屏布局重排（倒计时36px/底部扁平化） | ExploreScreen.lua | 1h |
| P0 | 瓦片渲染去格线（径向渐变替代nvgRect填色） | InkTileRenderer.lua | 1h |
| P0 | 新增 FogOfWar 模块 | FogOfWar.lua（新） | 1h |
| P0 | 瓦片迷雾渲染（DARK/EXPLORED/VISIBLE） | InkTileRenderer.lua | 1h |
| P0 | 迷雾边缘柔化（径向渐变） | InkRenderer.lua | 0.5h |
| P0 | 实体可见性判定 | ExploreScreen.lua | 1h |
| P0 | 灾变瘴气吞噬迷雾 | Timer + FogOfWar 联动 | 0.5h |
| P0 | BeastAI 朝向系统 | BeastAI.lua | 1h |
| P0 | 接触角度判定（偷袭/正面） | ExploreScreen.lua | 0.5h |
| P0 | 偷袭捕获加成 | CaptureSystem.lua | 0.5h |
| P0 | 朝向视觉指示（扇形） | BeastRenderer.lua | 0.5h |
| P1 | 偷袭/警觉特效（"袭"/"!"） | InkRenderer.lua | 0.5h |
| P1 | 实体具象化渲染（玩家斗笠/线索爪印/资源白描） | InkRenderer.lua | 2h |
| P1 | BeastData 扩展至 10 种异兽 | BeastData.lua | 1h |
| P1 | 5 种新异兽水墨形状 | BeastRenderer.lua | 3h |

### Phase 3: 体验完善（未开始）

| 任务 | 预估 |
|------|------|
| CaptureOverlay 完整封印演出 | 2h |
| SSR 揭示演出（水墨金光序列） | 2h |
| BookScreen 图鉴（三状态） | 1.5h |
| PrepareScreen 进场准备 | 1h |
| CraftSystem + CraftScreen | 1h |
| GameState 完整存档 | 1h |

### Phase 4: 留存系统（未开始）

| 任务 | 预估 |
|------|------|
| DailySystem + DailyScreen | 1h |
| TutorialSystem 新手引导 | 1.5h |
| 质量分级自动降级调优 | 1h |
| TextureCache 可选贴图层 | 1h |

---

## 核心玩法流程

```
大厅(LobbyScreen)
  │ 踏入灵境
  ▼
进场准备(PrepareScreen) — 未实现
  │
  ▼
探索(ExploreScreen) ← 核心
  │
  ├── 移动探索（虚拟摇杆 + 战争迷雾渐进披露）
  ├── 采集资源（接触自动拾取）
  ├── 调查线索（点击 → 进度条 → 品质触发）
  ├── 接触异兽（判定偷袭/正面/侧面）
  │     ├── 偷袭 → 加成进入压制
  │     ├── 正面 → 50%逃跑 / 50%进入压制
  │     └── 侧面 → 正常进入压制
  │
  ├── push → SuppressOverlay（压制QTE）
  │     ├── 成功 → 封灵器捕获判定
  │     │     ├── 成功 → 灵契入包
  │     │     └── 失败 → 异兽转警觉
  │     └── 失败 → 异兽逃跑
  │
  ├── 到达撤离点 → 站定3秒
  │     ├── 灵契稳定 → 直接成功
  │     └── 灵契不稳定 → push → ContractQTEOverlay
  │           ├── QTE成功 → 灵契保留
  │           └── QTE失败 → 灵契破碎
  │
  └── 灾变超时(8分钟) → 强制结算
        │
        ▼
结算(ResultScreen)
  │ 归返山海
  ▼
大厅(LobbyScreen)
```

---

## 技术备忘

- **坐标系**: 世界 Y-up（地图左下原点），屏幕 Y-down（NanoVG），Camera 统一转换
- **渲染事件**: 所有 NanoVG 绘制必须在 `NanoVGRender` 事件回调内
- **字体**: `nvgCreateFont` 只在 `Start()` 调用一次
- **输入流**: Touch → VirtualJoystick → InputRouter → Screen.onInput
- **事件总线**: owner 机制确保屏幕退出时批量注销
- **存档路径**: `fileSystem:CreateDir("saves")` 确保目录存在
- **视觉核心约束**: 无格线、无图标化实体、无撤离按钮、无局内跨局资源显示（详见 ui.md 第一章）
