# NoteReview App — AGENTS.md

## 项目定位
Flutter Android 应用，AI + 遗忘曲线复习 Obsidian 笔记。31 个 Dart 文件，~2500 行代码。

## 关键架构决策
- **状态管理**: Riverpod
- **数据库**: Drift 2.28.2，所有查询直接写在 `AppDatabase` 类中（不用 DAO 类，避免 `@DriftAccessor` 兼容性问题）
- **路由**: GoRouter + ShellRoute（3 Tab 底部导航）
- **AI**: DeepSeek API 直连（OpenAI 兼容格式）
- **通知**: Workmanager（本地 patch 版本，移除了废弃的 v1 Android API）

## 已知问题 / 待修复
1. **workmanager 本地补丁** — `packages/workmanager/` 是对 0.5.2 的 Kotlin patch，后续应升级到官方新版
2. **FilePicker 路径** — settings_screen 的 `_resolvePath()` 处理 content URI 转真实路径，实测可能需调整
3. **遗忘曲线概览** — 首页的「遗忘曲线概览」区域未实现，显示「即将支持」
4. **Drift 编译** — 改数据库表后必须跑 `dart run build_runner build --delete-conflicting-outputs`
5. **Android 编译标志** — 当前需 `--android-skip-build-dependency-validation`，因为 Gradle/AGP/Kotlin 版本匹配问题

## 编译命令（按顺序）
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --android-skip-build-dependency-validation
```

## 关键文件索引
| 文件 | 职责 |
|------|------|
| `lib/app.dart` | GoRouter + 3 Tab + 逾期检测 |
| `lib/data/database/database.dart` | AppDatabase（5 表 + 所有查询方法） |
| `lib/services/sm2_engine.dart` | SM-2 遗忘曲线算法 |
| `lib/services/ai_service.dart` | DeepSeek API 客户端 |
| `lib/services/prompt_service.dart` | Prompt 模板 + 响应解析 |
| `lib/services/vault_service.dart` | .md 文件递归扫描 |
| `lib/services/permission_service.dart` | Android 存储权限请求 |
| `lib/services/notification_service.dart` | WorkManager + 本地通知 |
| `lib/features/review/review_provider.dart` | 复习状态机 + Riverpod 逻辑 |
| `packages/workmanager/` | 本地 patch 的 workmanager 插件 |
| `docs/superpowers/specs/2026-07-24-note-review-app-design.md` | 完整设计文档 |
| `docs/superpowers/plans/2026-07-24-note-review-app.md` | 24 个任务的实现计划 |

## 使用流程
1. App → 设置 → 填 DeepSeek API Key → 选择笔记文件夹（弹权限）
2. 首页右上角 → 管理笔记 → 勾选要复习的笔记（含 `#review` 标签的自动识别）
3. 每晚 8 点有逾期笔记时通知 → 复习（AI 出题→作答→评价→评分→追问）
4. 复习完后可自由聊天

## 遗留 TODO
- [ ] 首页遗忘曲线可视化图表
- [ ] 自由聊天上下文携带用户笔记库
- [ ] workmanager 升级到官方兼容版本
- [ ] 暗色主题自动跟随系统
- [ ] 设置中遗忘曲线间隔自定义
