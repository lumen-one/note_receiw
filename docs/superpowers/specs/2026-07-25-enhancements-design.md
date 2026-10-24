# NoteReview App — 功能增强设计文档

> 基于用户反馈的 VaultBrowser 文件夹树、搜索、@笔记聊天复习、以及 AGENTS.md 遗留 TODO 的完整设计

---

## 1. VaultBrowser 文件夹树 + 搜索

### 1.1 树形数据结构

`VaultService.scanDirectory()` 当前返回扁平 `List<VaultEntry>`，重构为返回树结构：

```dart
class VaultTreeNode {
  final String name;           // 文件夹或文件名
  final String relativePath;   // 相对 vault 路径
  final String absolutePath;   // 绝对路径
  final bool isDirectory;
  final bool hasReviewTag;     // 仅文件有效
  final List<VaultTreeNode> children;  // 仅目录有效
}
```

扫描逻辑改为非递归的逐层扫描：对每个目录调用 `entity.list()` 而非 `entity.list(recursive: true)`，构建树。`#review` 标签仅在 `.md` 文件扫描时检查。

### 1.2 UI 布局

```
┌─────────────────────────────┐
│ 🔍 搜索笔记...      [搜索] │  ← 搜索栏
├─────────────────────────────┤
│ 📁 文件夹A (3)              │  ← ExpansionTile
│  ├─ 📄 笔记1.md  [#] [切换] │  ← 可切换激活
│  ├─ 📄 笔记2.md       [切换]│
│  └─ 📁 子文件夹 (1)         │
│     └─ 📄 笔记3.md  [#] [切换]│
│ 📁 文件夹B (0)              │
│ 📄 根笔记.md         [切换]  │
└─────────────────────────────┘
```

- 文件夹用 `ExpansionTile`，默认折叠
- 文件夹后显示该目录下 `.md` 文件总数（含子目录）
- 文件用 `NoteTile`（现有 widget，保持不变）
- 带 `#review` 标签的文件显示 `#` 标记
- 搜索时：所有匹配结果扁平展示，每行显示路径和文件名高亮

### 1.3 搜索实现

- 顶部 `TextField`，`onChanged` 时过滤 `_allEntries`（扁平缓存）
- 匹配规则：文件名包含搜索词（大小写不敏感）
- 搜索模式下切换回扁平 `ListView`，每行显示 `📄 文件夹/子文件夹/笔记.md`
- 清除搜索恢复树形

### 1.4 数据变更

`VaultService` 新增方法：

```dart
Future<VaultTreeNode> scanTree(String rootPath)  // 返回树
List<VaultEntry> flattenTree(VaultTreeNode node)  // 转扁平列表（用于搜索）
```

---

## 2. @笔记聊天 + 复习联动

### 2.1 聊天输入框改造

在 `ChatScreen` 中，`TextField` 增加 `@` 检测：

```
检测逻辑：
  1. 监听 onChanged，获取光标位置前的文本
  2. 如果最后一个非空字符是 @ 或者匹配 @xxx 模式，进入补全模式
  3. 弹出 Overlay（SuggestionsList），显示已监控笔记列表
  4. 过滤：匹配已输入的部分（@后文本）
  5. 选中后，将 @xxx 替换为带样式的标记
     - 已监控笔记 → 蓝色 Chip + 文件名
     - 未监控笔记 → 灰色 Chip + 文件名 + "未监控" 标记
```

UI 示意：

```
┌─────────────────────────────┐
│ 输入框：我学习了 @笔记     │
│                          │
│  ┌─────────────────────┐  │
│  │ 📄 笔记1.md (已监控) │  │  ← SuggestionsList
│  │ 📄 笔记2.md (已监控) │  │
│  │ 📄 笔记3.md (未监控) │  │
│  └─────────────────────┘  │
└─────────────────────────────┘
```

实现方式：使用 `CompositedTransformFollower` + `CompositedTransformTarget` 实现 Overlay 定位。或者简化为在输入框下方显示一个 `Column` 建议列表。

由于 Flutter TextField 原生不支持富文本 Chip 编辑，采用简化方案：
- 输入 `@` 后弹出笔记选择列表
- 选中后文本替换为 `@笔记名` 纯文本格式
- 同时在内存中记录 `_mentionedNoteIds: Set<int>`
- 发送时将 `@笔记名` 替换为完整文件路径上下文

### 2.2 笔记上下文注入

发送消息时，系统 prompt 自动包含 @mention 笔记的内容：

```
系统 prompt 改为：
你是一位和我一起学习的挚友。用户可以 @ 笔记名 来引用笔记内容。
当前会话引用的笔记：
- 笔记1.md（来自 文件夹/笔记1.md）：
{笔记1的内容摘要或全文}
- 笔记2.md（来自 文件夹/笔记2.md）：
{笔记2的内容摘要或全文}

请基于以上笔记内容进行讨论。
```

- 笔记内容截取前 2000 字符（防止 token 超限）
- @ 同篇笔记多次不重复添加

### 2.3 复习联动

聊天结束时（用户显式点击"结束聊天"或返回时），对本次 @mention 的已监控笔记执行 SM-2 复习更新：

```
逻辑：
  1. 收集 _mentionedNoteIds 中处于监控状态（is_active=true）的笔记
  2. 对每篇笔记调用 Sm2Engine.calculate(quality: 3, ...)
     - quality=3 表示"答对但勉强"——聊天复习质量中等
  3. 更新 review_records 表的 sm2 字段
  4. 更新 next_review_date
  5. 在 chat_messages 表记录一条系统消息
  6. 显示 SnackBar："已通过聊天复习 N 篇笔记"
```

聊天入口改造：`ChatScreen` 现在可以接收可选参数 `initialNoteIds`（从 VaultBrowser 直接进入聊天）。

### 2.4 路由更新

```
新路由：
  /review/chat?notes=id1,id2   → 携带预设笔记的聊天
  /review/chat                 → 空聊天（仍可通过 @ 添加）
```

---

## 3. 首页遗忘曲线概览图表

### 3.1 依赖

添加 `fl_chart: ^0.69.0` 到 pubspec.yaml。

### 3.2 数据

新增数据库查询（`AppDatabase` 中）：

```dart
Future<List<DailyReviewCount>> reviewHistoryLast30Days()
```

返回近 30 天每天完成的复习数（从 `review_records.last_review_date` 统计）。

### 3.3 UI

```
┌─────────────────────────────┐
│ 遗忘曲线概览                │
│                             │
│  复习次数                   │
│  ██                         │
│  ██ ██                      │
│  ██ ██ ██    ██             │
│  ██ ██ ██ ██ ██ ██          │
│  ────────────────────       │
│  07/01   07/15   07/25      │
│                             │
│  今日待复习: 5篇             │
└─────────────────────────────┘
```

使用 `fl_chart` 的 `LineChart` 或 `BarChart`，显示近 30 天复习趋势。简单柱状图。

---

## 4. 暗色主题自动跟随系统

`app.dart` 中一行变更：

```dart
// 修改前
return MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  routerConfig: router,
);

// 修改后
return MaterialApp.router(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ThemeMode.system,  // 新增
  routerConfig: router,
);
```

---

## 5. 设置中遗忘曲线间隔自定义

### 5.1 存储

`SettingsStore` 新增：

```dart
static const _keyIntervals = 'sm2_intervals';  // JSON array

static Future<List<int>> getSm2Intervals() async {
  final prefs = await _prefs;
  final json = prefs.getString(_keyIntervals);
  if (json == null) return [1, 6, 15, 38, 95, 238];
  return (jsonDecode(json) as List).cast<int>();
}

static Future<void> setSm2Intervals(List<int> intervals) async {
  final prefs = await _prefs;
  await prefs.setString(_keyIntervals, jsonEncode(intervals));
}
```

### 5.2 SM-2 引擎改造

`Sm2Engine.calculate()` 增加可选参数 `customIntervals`：

```dart
static Sm2Result calculate({
  required int quality,
  required double currentInterval,
  required double currentEaseFactor,
  required int currentRepetitions,
  List<int>? customIntervals,  // 新增
})
```

使用自定义间隔代替硬编码的 `[1, 6, ...]`。

### 5.3 UI

设置页新增"遗忘曲线间隔"编辑区：

```
┌─────────────────────────────┐
│ 遗忘曲线间隔天数            │
│                             │
│  第1次: [1] 天  [✕]        │
│  第2次: [6] 天  [✕]        │
│  第3次: [15] 天 [✕]        │
│  第4次: [38] 天 [✕]        │
│  [+ 添加间隔]               │
│                             │
│  [恢复默认]                 │
└─────────────────────────────┘
```

每个间隔可编辑数字，可删除，底部的 "添加间隔" 追加新行。

---

## 6. 变更文件一览

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `lib/services/vault_service.dart` | 重构 | 新增 `scanTree()` 方法，保留向后兼容 |
| `lib/features/vault/vault_browser_screen.dart` | 重写 | ExpansionTile 树 + 搜索栏 |
| `lib/services/vault_provider.dart` | 新增 | `vaultTreeProvider` |
| `lib/features/review/chat_screen.dart` | 重写 | @ 补全 + 笔记上下文 + 复习联动 |
| `lib/features/review/review_provider.dart` | 扩展 | 新增 `chatReviewProvider` / 复习联动逻辑 |
| `lib/features/home/home_screen.dart` | 修改 | 图表区域替换"即将支持" |
| `lib/features/home/home_provider.dart` | 扩展 | 新增 `reviewHistoryProvider` |
| `lib/data/database/database.dart` | 扩展 | 新增 `reviewHistoryLast30Days()` 查询 |
| `lib/data/settings_store.dart` | 扩展 | 新增间隔存储方法 |
| `lib/services/sm2_engine.dart` | 修改 | 支持自定义间隔 |
| `lib/features/settings/settings_screen.dart` | 扩展 | 新增间隔编辑 UI |
| `lib/app.dart` | 修改 | 添加 `ThemeMode.system` |
| `pubspec.yaml` | 修改 | 添加 `fl_chart` 依赖 |

---

## 7. 工作量估算

| 模块 | 预计改动行数 | 复杂度 |
|------|------------|--------|
| VaultBrowser 文件夹树 + 搜索 | ~250 行 | ⭐⭐⭐ |
| @ 笔记聊天 + 复习联动 | ~200 行 | ⭐⭐⭐ |
| 遗忘曲线概览图表 | ~80 行 | ⭐⭐ |
| 动画主题自动跟随 | ~1 行 | ⭐ |
| 遗忘曲线间隔自定义 | ~100 行 | ⭐⭐ |
| **合计** | **~630 行** | |

所有改动仅涉及 Dart 代码，不涉及数据库迁移（schema version 不变）。
