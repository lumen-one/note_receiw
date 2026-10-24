# NoteReview App — 设计文档

> 基于遗忘曲线 + AI 的 Obsidian 笔记复习助手

## 1. 项目概述

一款 Android Flutter 应用，扫描手机本地 Obsidian Vault 中的 Markdown 笔记，利用 DeepSeek API 根据笔记内容实时生成简答题，基于 SM-2 遗忘曲线算法安排复习间隔，帮助用户高效巩固笔记知识。

### 核心功能

| 功能 | 描述 |
|------|------|
| 文件扫描 | 浏览本地 vault 文件夹，递归扫描所有 `.md` 文件 |
| 笔记选择 | 手动勾选 + 自动识别 `#review` 标签 |
| AI 出题 | 实时调用 DeepSeek 读取笔记生成简答题 + 拓展内容 |
| SM-2 遗忘曲线 | 用户自评驱动间隔调度（1→2→4→7→15→30→60 天） |
| 复习 + 追问 | 逐题作答，每道题答后可与 AI 追问讨论 |
| 自由聊天 | 全部复习完成后可自由聊天 |
| 逾期检测 | App 前台时检测逾期笔记，不依赖后台 |
| 通知辅助 | WorkManager + 本地通知，晚 8 点弹窗提醒（可选） |

---

## 2. 架构设计

### 方案选择：纯客户端

Flutter App 直连 DeepSeek API，SQLite 本地存储，API Key 用 `flutter_secure_storage` 加密。

```
┌────────────────────────────────────────────────────┐
│                  Flutter App                        │
├────────────────────────────────────────────────────┤
│  Bottom Navigation (3 tabs)                       │
│  ├── 🏠 Home       仪表盘 + VaultBrowser(右上角)   │
│  ├── 📝 Review      复习流程 + 自由聊天            │
│  └── ⚙️ Settings    配置 + API Key                │
├────────────────────────────────────────────────────┤
│  Business Logic (Riverpod Providers)               │
│  ├── VaultService      扫描md / 解析标签          │
│  ├── ReviewService     SM-2引擎 / 会话管理         │
│  ├── AIService         DeepSeek API 调用          │
│  └── NotificationSvc   WorkManager 调度            │
├────────────────────────────────────────────────────┤
│  Data Layer                                       │
│  ├── SQLite (drift)    复习状态 / 聊天记录         │
│  └── SecureStorage     API Key 加密               │
├────────────────────────────────────────────────────┤
│  External                                         │
│  ├── Android FileSystem  读取 Obsidian vault       │
│  └── DeepSeek API        https://api.deepseek.com  │
└────────────────────────────────────────────────────┘
```

---

## 3. 页面与路由

| 页面 | 路由 | 说明 |
|------|------|------|
| `HomeScreen` | `/` | 底部导航首页：复习统计 + 右上角 VaultBrowser 入口 |
| `VaultBrowser` | push | 全屏：文件夹树 + `.md` 列表 + 勾选/标签状态 |
| `ReviewSession` | `/review/start` | 主复习流程：题目列表 → 逐题作答 → 追问 |
| `FreeChat` | `/review/chat` | 自由聊天模式（复习后或无任务时进入） |
| `SettingsScreen` | `/settings` | API Key、vault 路径、Prompt 模板、遗忘曲线参数、通知时间 |

### 复习 Tab 状态机

```
┌─────────────────────────────────────────────┐
│  Review Tab                                 │
│                                             │
│  [无逾期笔记]                               │
│   └─ 空白页 "暂无待复习笔记"               │
│      └─ [随便聊聊] → FreeChat              │
│                                             │
│  [有逾期笔记]                               │
│   └─ "你有 N 篇笔记待复习"                 │
│      └─ [开始复习] → ReviewSession          │
│         ├─ 题目列表 (3-5 题一次性展示)      │
│         ├─ 逐题：                           │
│         │  [题目] → [输入答案] → [提交]     │
│         │  → [AI 评价 + 拓展问题]           │
│         │  → [自评 0-5 分]                  │
│         │  → [追问?] → 追问聊天 → 返回      │
│         │  → [下一题]                       │
│         └─ 全部完成 → FreeChat              │
└─────────────────────────────────────────────┘
```

---

## 4. 数据模型 (SQLite / Drift)

```sql
-- 笔记文件
CREATE TABLE note_files (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path     TEXT NOT NULL,           -- 相对 vault 根路径
  file_name     TEXT NOT NULL,
  added_manually INTEGER DEFAULT 0,      -- 是否手动添加
  has_review_tag INTEGER DEFAULT 0,      -- 是否含 #review 标签
  is_active     INTEGER DEFAULT 1,       -- 是否参与复习
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

-- 复习记录 (每个笔记一条，存 SM-2 状态)
CREATE TABLE review_records (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id          INTEGER NOT NULL REFERENCES note_files(id) UNIQUE,
  sm2_interval     REAL DEFAULT 1.0,     -- 当前间隔 (天)
  sm2_ease_factor  REAL DEFAULT 2.5,     -- 难度系数
  sm2_repetitions  INTEGER DEFAULT 0,    -- 连续答对次数
  next_review_date INTEGER NOT NULL,     -- 下次复习时间戳
  last_review_date INTEGER,              -- 上次复习时间戳
  last_score       INTEGER,              -- 上次自评 0-5
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL
);

-- 聊天消息
CREATE TABLE chat_messages (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  session_type TEXT NOT NULL,             -- 'question_followup' | 'free_chat'
  note_id      INTEGER REFERENCES note_files(id),
  role         TEXT NOT NULL,             -- 'user' | 'assistant'
  content      TEXT NOT NULL,
  created_at   INTEGER NOT NULL
);

-- 应用状态 (单例)
CREATE TABLE app_state (
  id                INTEGER PRIMARY KEY CHECK (id = 1),
  last_check_time   INTEGER NOT NULL      -- 上次检查复习的时间戳
);

-- Prompt 模板
CREATE TABLE prompt_templates (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  name      TEXT NOT NULL UNIQUE,         -- 'generate_question' | 'evaluate_answer'
  content   TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

---

## 5. 核心引擎

### 5.1 SM-2 遗忘曲线算法

```
输入: quality (用户自评 0-5), 当前 sm2 状态
输出: 更新后的 sm2 状态

IF quality >= 3:   # 答对
  IF repetitions == 0: interval = 1
  ELSE IF repetitions == 1: interval = 6
  ELSE: interval = round(interval * ease_factor)
  repetitions += 1
ELSE:               # 答错
  interval = 1
  repetitions = 0

ease_factor = ease_factor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
ease_factor = max(1.3, ease_factor)

next_review_date = today + interval 天
```

默认间隔序列（ease_factor=2.5 时）：**1 → 6 → 15 → 38 → 95 → 238 ... 天**

后续支持用户在设置中自定义每个阶段的间隔天数。

### 5.2 逾期检测引擎

```
数据库字段: app_state.last_check_time

[每次 App 进入前台（onResume）]：
  1. now = DateTime.now().millisecondsSinceEpoch
  2. last_check = SELECT last_check_time FROM app_state WHERE id = 1
  3. 查询逾期笔记：
     SELECT nr.*, nf.file_name
     FROM review_records nr
     JOIN note_files nf ON nr.note_id = nf.id
     WHERE nf.is_active = 1
       AND nr.next_review_date > last_check
       AND nr.next_review_date <= now
  4. UPDATE app_state SET last_check_time = now

[逾期 > 0]：
  - HomeScreen Tab 显示红色角标 (逾期数量)
  - Review Tab 展示逾期笔记列表
  - 用户点入触发复习流程

[逾期 = 0]：
  - 静默

[WorkManager 辅助]：
  - 每 15 分钟检查，约 20:00 时如逾期 > 0 弹窗通知
  - 非强依赖：即使被杀后台，下次打开 App 仍能检测逾期
```

### 5.3 复习会话流程

```
1. 选笔记：ORDER BY next_review_date ASC LIMIT 5
2. 对每篇笔记调用 DeepSeek (并行请求)：
   - 读取文件内容
   - 套用 generate_question Prompt 模板
   - 返回：题目 + 拓展知识点
3. 展示 3-5 道题目列表
4. 用户逐题：
   a. 阅读题目
   b. 在文本框中输入答案 -> 提交
   c. AI 评价（套用 evaluate_answer Prompt）
      - 评价内容 + 建议评分 + 延伸问题
   d. 用户自评 0-5 分（可参考 AI 建议）
   e. SM-2 更新
   f. 可选追问：进入聊天模式，可多轮对话
   g. 下一题
5. 全部完成后进入自由聊天模式
```

---

## 6. AI 集成

### 6.1 DeepSeek API

- Endpoint: `https://api.deepseek.com/v1/chat/completions`
- Model: `deepseek-chat`
- 认证: `Authorization: Bearer <API_KEY>`

### 6.2 Prompt 模板（默认，可在设置中自定义）

**出题 Prompt** (`generate_question`)：

```
你是一位和我一起学习的挚友。请阅读以下笔记内容，帮我查漏补缺：

1. 生成一道简答题，检验我对内容的理解
2. 根据笔记内容，拓展一个相关知识或概念，帮我开阔思路

笔记内容：
{note_content}

请按以下格式回复：
【题目】
(题目内容)

【拓展】
(拓展知识点或概念)
```

**评价 Prompt** (`evaluate_answer`)：

```
你是和我一起学习的挚友。以下是笔记、你出的题和我的回答。

笔记：
{note_content}

题目：
{question}

我的回答：
{user_answer}

请：
1. 温和地评价我的回答，指出遗漏的关键点
2. 建议评分 0-5 分（0=完全错误, 5=完全正确且完整）
3. 提出一个延伸问题，引导我深入思考

请按以下格式回复：
【评价】
(评价内容)

【建议评分】
(0-5 的整数)

【延伸】
(延伸问题)
```

### 6.3 聊天模式 Context

- **追问模式**：携带笔记内容 + 题目 + 用户回答 + AI 评价作为 context，多轮对话
- **自由聊天模式**：初始无特定 context，用户可自由提问，绑定最近复习的笔记列表作为知识背景

---

## 7. 通知机制

| 组件 | 用途 |
|------|------|
| `workmanager` | 后台 periodic task，每 15 分钟检查一次 |
| `flutter_local_notifications` | 本地推送，标题「复习时间到」 |
| `app_state.last_check_time` | 持久化检测时间，补救后台被杀场景 |

```
WorkManager.registerPeriodicTask(
  "review_check",
  frequency: Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.not_required),
)

Task 逻辑：
  now = DateTime.now()
  if now.hour == 20 || (now.hour == 20 && now.minute < 15):
    overdue = queryOverdueNotes()
    if overdue.isNotEmpty:
      showNotification(
        title: "复习时间到",
        body: "你有 ${overdue.length} 篇笔记需要复习",
        payload: "/review",  // 点击打开 Review Tab
      )
```

---

## 8. 设置页面

| 设置项 | 类型 | 说明 |
|--------|------|------|
| DeepSeek API Key | 密码输入框 | 存储到 `flutter_secure_storage` |
| Obsidian Vault 路径 | 文件夹选择器 | 用户选择本地文件夹根目录 |
| 出题 Prompt | 多行文本编辑器 | 可编辑模板，`{note_content}` 为占位符 |
| 评价 Prompt | 多行文本编辑器 | 可编辑模板，`{note_content}`, `{question}`, `{user_answer}` 为占位符 |
| 遗忘曲线间隔 | 动态列表编辑 | 默认 [1, 6, 15, 38, 95, 238]，可增删改 |
| 通知时间 | 时间选择器 | 默认 20:00 |
| 每次复习题数 | 数字输入 | 默认 5，范围 1-10 |

---

## 9. 依赖清单

```yaml
dependencies:
  flutter:
    sdk: flutter
  drift: ^2.x              # SQLite ORM
  sqlite3_flutter_libs: ^0.x
  riverpod: ^2.x           # 状态管理
  flutter_riverpod: ^2.x
  go_router: ^14.x         # 路由
  workmanager: ^0.5.x      # 后台任务
  flutter_local_notifications: ^17.x
  flutter_secure_storage: ^9.x
  dio: ^5.x                # HTTP 客户端
  path_provider: ^2.x      # 文件路径
  permission_handler: ^11.x  # 存储权限
  file_picker: ^8.x        # 文件夹选择
  path: ^1.x               # 路径处理
  freezed_annotation: ^2.x # 数据类生成
  json_annotation: ^4.x    # JSON 序列化

dev_dependencies:
  drift_dev: ^2.x
  build_runner: ^2.x
  freezed: ^2.x
  json_serializable: ^6.x
  flutter_lints: ^4.x
```

---

## 10. 开发阶段

| 阶段 | 内容 | 关键产出 |
|------|------|----------|
| **P0** | Flutter 初始化、路由、底部导航、Riverpod 架构、空页面骨架 | 可运行的空 App |
| **P1** | 数据层：Drift 数据库定义、DAO、Repository、SM-2 算法、SecureStorage | 数据持久化 |
| **P2** | Vault 模块：权限请求、文件递归扫描、md 解析、标签识别、VaultBrowser UI | 文件浏览选择 |
| **P3** | AI 服务：DeepSeek HTTP 客户端、Prompt 模板引擎、出题/评价/聊天接口 | AI 集成 |
| **P4** | 复习流程：ReviewSession 页面、答题/评价/自评/追问完整流程、自由聊天 | 核心功能 |
| **P5** | 通知与逾期：WorkManager、本地通知、app_state 逾期检测、角标 | 提醒系统 |
| **P6** | 设置：API Key、路径选择、Prompt 编辑、遗忘曲线自定义、通知时间 | 可配置化 |
| **P7** | 打磨：错误处理、loading 状态、空状态、边距、暗色主题、性能优化 | 完整体验 |

---

## 11. 文件结构

```
lib/
├── main.dart
├── app.dart                        # MaterialApp + GoRouter
├── core/
│   ├── constants.dart
│   ├── theme.dart
│   └── extensions.dart
├── data/
│   ├── database/
│   │   ├── database.dart           # Drift database 定义
│   │   ├── tables.dart             # 表定义
│   │   └── daos/
│   │       ├── note_dao.dart
│   │       ├── review_dao.dart
│   │       └── chat_dao.dart
│   ├── repositories/
│   │   ├── note_repository.dart
│   │   ├── review_repository.dart
│   │   ├── chat_repository.dart
│   │   └── settings_repository.dart
│   └── secure_storage.dart
├── services/
│   ├── vault_service.dart          # 文件扫描+标签解析
│   ├── sm2_engine.dart             # SM-2 算法
│   ├── ai_service.dart             # DeepSeek API
│   ├── prompt_service.dart         # Prompt 模板渲染
│   ├── review_session_service.dart # 复习会话管理
│   └── notification_service.dart   # WorkManager + 通知
├── features/
│   ├── home/
│   │   ├── home_screen.dart
│   │   ├── home_provider.dart
│   │   └── widgets/
│   │       ├── stats_card.dart
│   │       └── overdue_badge.dart
│   ├── vault/
│   │   ├── vault_browser_screen.dart
│   │   ├── vault_provider.dart
│   │   └── widgets/
│   │       ├── file_tree.dart
│   │       └── note_tile.dart
│   ├── review/
│   │   ├── review_screen.dart
│   │   ├── review_provider.dart
│   │   ├── review_session_screen.dart
│   │   ├── chat_screen.dart
│   │   └── widgets/
│   │       ├── question_card.dart
│   │       ├── answer_input.dart
│   │       ├── evaluation_view.dart
│   │       ├── self_rating_bar.dart
│   │       └── chat_bubble.dart
│   └── settings/
│       ├── settings_screen.dart
│       ├── settings_provider.dart
│       └── widgets/
│           ├── api_key_field.dart
│           ├── vault_path_picker.dart
│           ├── prompt_editor.dart
│           ├── interval_list_editor.dart
│           └── time_picker.dart
└── models/
    ├── note_file.dart
    ├── review_record.dart
    └── chat_message.dart
```

---

## 12. 非功能需求

| 类别 | 要求 |
|------|------|
| 最低 Android 版本 | API 26 (Android 8.0) |
| 存储权限 | `READ_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` (Android 11+) |
| 网络 | 仅需出题和聊天时，支持离线查看复习状态 |
| 错误处理 | API 调用失败时重试 2 次，超时 30s，失败提示用户手动重试 |
| 性能 | 文件扫描异步执行，大 vault（1000+文件）不阻塞 UI |
| 隐私 | API Key 仅存本地 SecureStorage，不上传 |
