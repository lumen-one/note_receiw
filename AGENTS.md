# NoteReview App — AGENTS.md

## 项目定位
Flutter Android 应用，AI + 遗忘曲线复习 Obsidian 笔记。本文件位于仓库根目录（本地路径 `phone_note_receiw/phone_note_reviewIDET/`），下文所有命令均在仓库根目录执行。

## 关键架构决策
- **状态管理**: Riverpod（`lib/features/*/` 下各模块有自己的 provider 文件）
- **数据库**: Drift 2.x, 5 表（`NoteFiles`, `ReviewRecords`, `ChatMessages`, `AppState`, `PromptTemplates`），所有查询方法直接写在 `AppDatabase`（不用 DAO，避免 `@DriftAccessor` 兼容性问题）
- **路由**: GoRouter + ShellRoute（3 Tab: 首页/复习/设置），非 Tab 页（vault-browser, review/start, review/chat, /notes）使用 root navigator。`/review/chat` 支持 `?notes=` 和 `?session=` 查询参数
- **AI**: DeepSeek API 直连（OpenAI 兼容格式），API Key 存 `flutter_secure_storage`。支持 SSE 流式输出（`chatStream` / `continueChatStream`），可传 `CancelToken` 取消，`onFinish` 回传 `finish_reason` 用于判断是否被 `max_tokens` 截断
- **复习会话**: 一次最多处理 N 篇逾期笔记（设置项，默认 3），每篇一次流式请求。流式阶段只用 `parseCompletedQuestions` 交付**已闭合**的题目块，流结束后再 `isFinal: true` 补齐最后一块
- **通知**: Workmanager（本地 patch 0.5.2）每 15 分钟检查逾期，`flutter_local_notifications` 弹出提醒
- **深色模式**: `ThemeMode.system` 跟随系统

## 编译命令（按顺序）
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --android-skip-build-dependency-validation
```
- 依赖版本由 `pubspec.lock` 锁定并已入库，`flutter pub get` 按锁定版本安装；增删依赖后要把 lockfile 一起提交

## 数据库
- schema version 2（v1→v2 迁移: 给 `note_files` 加 `tags` 列）
- 改表后必须跑 `dart run build_runner build --delete-conflicting-outputs`
- 生成的 `*.g.dart` / `*.freezed.dart` 在 `.gitignore` 中
- 数据库文件: `getApplicationDocumentsDirectory()/note_review.db`

## 已知问题
1. **workmanager 本地补丁** — `packages/workmanager/` 是对 0.5.2 的 Kotlin patch，后续应升级到官方新版
2. **Android 编译标志** — 当前需 `--android-skip-build-dependency-validation`（Gradle/AGP/Kotlin 版本匹配问题）
3. **缺少自动化 UI 测试** — 纯逻辑层（SM-2、解析器）已有单测，界面仍靠手测
4. **无法上架 Google Play** — `MANAGE_EXTERNAL_STORAGE` 属受限权限；`READ_EXTERNAL_STORAGE` 在 Android 13+ 已失效。当前分发方式只能是侧载
5. **依赖停维护** — `flutter_markdown` 已被官方归档（`flutter_math_fork` 也更新缓慢），升级 Flutter 前需评估
6. **models 目录为空** — 模型类内联在各 provider/service 文件中

## 测试
```bash
flutter test --no-pub     # 24 个用例：sm2_engine / prompt_service
```
- 若本机设了 `http_proxy`，flutter_tester 连不上本地 socket，需先 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`

## 设置项
- **DeepSeek API Key**: `flutter_secure_storage`
- **模型名**: `SharedPreferences` key `model_name`，默认 `deepseek-v4-flash`
- **SM-2 间隔**: `SharedPreferences` key `sm2_intervals`，JSON 数组，默认 `[1, 6, 15, 38, 95, 238]`
- **每次复习笔记数**: `SharedPreferences` key `session_note_limit`，默认 3，上限 10
- **每篇笔记出题数 / 通知时间**: `SharedPreferences`

## 注意点
- **FutureProvider 同步读陷阱**: 不要在 `StateNotifier` 中用 `.valueOrNull` 读 `FutureProvider`，必须用 `await provider.future` 等异步值算完。`reviewCountProvider` 踩过这个坑。
- **`ReviewState.copyWith` 用哨兵**: 可空字段的默认值是 `_unset`，传 `null` 才是清空。写成 `x ?? this.x` 会让 `errorMessage` / `statusMessage` 一旦设置就永远清不掉。
- **流式题目的切分边界**: 题目块只有在后面出现下一个 `【题目N】` 或流结束时才算写完。不要按 `【题目N】` 直接切分后就上屏 —— 最后一块的拓展字段随时会继续增长，是 `expansion` 空串、题号错位一类 bug 的来源。
- **取消与世代**: 每次 `loadQuestions` 会 `++_generation` 并新建 `CancelToken`，旧协程发现代号不符就退出；退页时 `stopGeneration()` 中断后台流。不要绕过这两个卫兵直接写 `state`。
- **逾期判定**: `overdueNotes` 用 LEFT JOIN 逻辑包含从未复习的笔记。`monitored_notes_screen` 中必须用 `isBefore(now)` 而非 `inDays <= 0` 判断逾期。
- **SM-2 多题评分**: 每篇笔记的多道题取评分平均值后写一次 SM-2 记录，延迟到切笔记或完成时写入（`_saveNoteRecord`，由 `_savedNotes` 防重复）。`submitSelfScore` 只更新内存状态，同一题重复点分只保留最后一次。
- **流式输出 SSE**: `ResponseBody.stream` 返回 `Stream<Uint8List>`，需要 `.cast<List<int>>().transform(utf8.decoder)` 转换类型。
- **笔记内容截断**: 读笔记统一走 `NoteContentLoader.load()`，出题上限 6000 字、聊天 2000 字，超长会截断并在界面提示。不要再直接 `readAsString()` 塞进 prompt。

## 待完成
- [ ] 复习多题拆成独立消息框（当前 3-5 题挤在一个消息框，不便阅读和作答）

## 安全说明
- **笔记只读**: App 仅通过 `File.readAsString()` / `File.readAsLines()` 读取 .md 文件内容，从不写入或修改原始笔记文件

## 代码约定
- `analysis_options.yaml` —— 继承 `flutter_lints`，开启 `prefer_const_constructors`/`prefer_const_declarations`，`avoid_print: false`
- 所有文件使用 `part 'file.g.dart'` 风格
- YAML frontmatter 标签提取在 `services/yaml_parser.dart`

## 关键文件索引
| 文件 | 职责 |
|------|------|
| `lib/app.dart` | GoRouter + ShellRoute + 30 秒逾期轮询 + AppLifecycle 检测 |
| `lib/main.dart` | 入口: 初始化通知、请求权限、ProviderScope |
| `lib/data/database/database.dart` | AppDatabase（5 表 + 所有查询方法） |
| `lib/services/sm2_engine.dart` | SM-2 遗忘曲线算法 |
| `lib/services/ai_service.dart` | DeepSeek API 客户端（Dio），含 SSE 流式方法 |
| `lib/services/prompt_service.dart` | Prompt 模板 + 响应解析（`【题目】`/`【评价】`/`【建议评分】`/`【延伸】`），含流式块闭合解析 `parseCompletedQuestions` |
| `lib/services/note_content.dart` | 笔记读取 + 超长截断（统一出题与聊天两条路径） |
| `lib/services/vault_service.dart` | .md 文件递归扫描 + YAML 标签提取 |
| `lib/services/notification_service.dart` | WorkManager + 本地通知 |
| `lib/features/review/review_provider.dart` | 复习状态机（ReviewNotifier）：会话生成、流式增量上屏、多题评分 |
| `lib/features/review/widgets/` | 题目卡、评价卡、聊天气泡、逾期列表弹窗 |
| `test/` | `sm2_engine_test.dart` / `prompt_service_test.dart` |
| `lib/features/review/chat_screen.dart` | 聊天页（自由/续聊），支持 SSE + 加载历史消息 |
| `lib/features/notes/note_detail_screen.dart` | 笔记详情：SM-2 状态 + 按日期分组会话 + 查看/续聊 |
| `lib/features/settings/settings_provider.dart` | 全局 Provider（database, API key, vault path 等） |
| `packages/workmanager/` | 本地 patch 的 workmanager 0.5.2 插件 |
| `docs/superpowers/specs/` | 完整设计文档 |
| `docs/superpowers/plans/` | 实现计划 |
