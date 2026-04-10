# 异兽贴图显示问题

## 概述

图鉴（BookScreen）和捕获成功（CaptureOverlay）界面中，异兽贴图存在两个已知问题。

---

## Bug 1: 首次捕获不显示贴图，降级为矢量

### 现象

游戏启动后**第一次**捕获异兽，捕获成功界面显示的是矢量程序化绘图，而非 PNG 贴图。之后再次捕获则能正常显示贴图。

### 原因分析

`BeastRenderer.initImages()` 在首次调用 `drawImage()` 时触发，内部通过 `nvgCreateImage()` 加载所有异兽贴图。但 `nvgCreateImage()` 可能是异步加载——调用后 handle 立即返回，但图片数据尚未就绪。此时 `drawImage()` 用该 handle 渲染时，图片实际未加载完成，导致渲染为空白，最终走进矢量降级分支。

### 相关代码

- `scripts/render/BeastRenderer.lua` → `initImages()` (约 L1495)
- `scripts/render/BeastRenderer.lua` → `drawImage()` (约 L1529)
- `scripts/screens/CaptureOverlay.lua` → L193: `BeastRenderer.drawImage(...)` 调用处

### 可能的修复方向

1. **预加载**：在游戏进入探索场景时就调用 `initImages()`，而非等到首次 `drawImage` 时才加载，给图片足够的加载时间
2. **加载状态检测**：如果引擎提供图片加载完成的回调或状态查询 API，可据此判断是否就绪
3. **重试机制**：首次 drawImage 失败时标记该 beast，下一帧重试贴图渲染

---

## Bug 2: 贴图宽高比不正确，横图被挤压为近似正方形

### 现象

贴图能显示后，所有图片都被渲染为近似正方形，无论原图是 16:9 横图还是 2:3 竖图。

### 原因分析

`nvgImageSize(vg, handle)` 在图片未完全加载时返回的宽高值不正确（可能返回 0 或默认值），导致计算出的宽高比 ratio 为 1.0（正方形）。

当前代码已改为延迟获取（在首次 `drawImage` 时才调用 `nvgImageSize`），但如果首次绘制时图片仍未完成加载，问题依旧存在。

### 贴图实际尺寸参考

| 异兽 | 文件 | 实际尺寸 | 宽高比 |
|------|------|----------|--------|
| SSR 001-006 | beast_001.png 等 | 2732x1532 | 1.78 (16:9) |
| R 017-024 | beast_017.png 等 | 2732x1532 | 1.78 (16:9) |

> 注：R 级 017-024 的所有贴图当前为同一张占位图（beast_002_xuancai.png 的副本）。

### 相关代码

- `scripts/render/BeastRenderer.lua` → `drawImage()` 中的 ratio 获取逻辑 (约 L1534)

### 可能的修复方向

1. **硬编码 ratio**：既然所有贴图都是 16:9，可以在 initImages 时直接设定 ratio = 16/9 作为 fallback
2. **预加载 + 延迟获取**：结合 Bug 1 的预加载方案，确保图片加载完成后再获取 nvgImageSize
3. **用 Image 资源获取尺寸**：通过 `cache:GetResource("Image", path)` 加载为 Urho3D Image 对象获取 width/height，这是同步操作，不受 NanoVG 异步影响

---

## 附：已修复的问题

### cache:Exists() 误判

**已修复**。原代码使用 `cache:Exists(path)` 预检查文件是否存在，但该 API 对 `image/beasts/` 路径下的文件始终返回 false，导致贴图从未被加载。已改为直接调用 `nvgCreateImage()` 并通过返回的 handle 值判断。

副作用：SR 级异兽（007-016）没有贴图文件，加载时会产生约 40 条 "Could not find resource" 的引擎日志，仅在初始化时出现一次，不影响运行。

---

## 贴图文件分布

| 品质 | ID 范围 | 贴图状态 |
|------|---------|----------|
| SSR | 001-006 | 有独立贴图（normal/yiwen/xuancai，部分有 xuancai_yiwen） |
| SR | 007-016 | **无贴图**，降级为矢量 |
| R | 017-024 | 有贴图但全部为占位图（同一张） |
