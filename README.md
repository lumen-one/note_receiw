# NoteReview

把 Obsidian 笔记变成一套复习计划：从 vault 里挑出到期的笔记，让 DeepSeek 出题，自己打分，按 SM-2 遗忘曲线算出下次该复习的时间。

## 怎么用

首次打开先在设置里填三样：DeepSeek API Key（存进 `flutter_secure_storage`，不进代码库）、笔记目录（用 Android 的系统目录选择器指定 vault）、每次复习几篇笔记（默认 3，上限 10）。每篇出几道题默认 5，可以改；SM-2 间隔默认按 1、6、15、38、95、238 天递推。

首页显示当前待复习篇数。进入复习后，App 按逾期顺序取笔记，逐篇流式生成题目，每道题除了题干还带一段【延伸】，把相关背景补上，省得再回头翻原文。答完可以自评 0–5 分，也可以只看不答。一篇笔记的几道题取平均分，写一条 SM-2 记录：分低间隔缩短，分高往后推。评分要等这篇笔记答完才落库，中途退出不会留下一半的记录。

除了复习，笔记详情页可以按日期翻历史会话，也能对任意一篇笔记开自由聊天，或者接着上次的对话继续聊。

## 技术栈

Flutter + Riverpod 管状态，Drift 存数据（`note_files`、`review_records`、`chat_messages`、`app_state`、`prompt_templates` 五张表，schema v2），GoRouter 走「首页 / 复习 / 设置」三个 Tab，其余页面挂 root navigator。网络层是 Dio，流式走 SSE，可取消。Workmanager 每 15 分钟检查一次逾期，用本地通知提醒。

调用的是 DeepSeek 的 OpenAI 兼容接口。出题走流式增量上屏：题目块在出现下一个【题目N】或流结束前不算写完，不会把只渲染了一半的【延伸】先贴到界面上。笔记超过 6000 字（聊天 2000 字）会被截断，并在界面提示。

## 构建

需要 Flutter SDK 和 Android SDK，以下命令都在仓库根目录执行：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --android-skip-build-dependency-validation
```

第二条不能省。Drift 生成的 `*.g.dart` 和 `*.freezed.dart` 都在 `.gitignore` 里，克隆下来必须先跑一遍生成，否则编译直接失败。

第三条带 `--android-skip-build-dependency-validation`，是因为本地 AGP / Kotlin 版本不满足 Flutter 的依赖校验，跳过即可，不影响产物。

依赖版本由 `pubspec.lock` 锁定并已入库，增删依赖后记得把 lockfile 一起提交。

## 测试

```bash
flutter test
```

24 个用例，覆盖 SM-2 算法（间隔递推、评分边界、同一题重复评分）和响应解析（流式块闭合、评分提取）。界面部分目前靠手测。

## 已知限制

只能侧载安装，上不了 Google Play。读写笔记目录用的是 `MANAGE_EXTERNAL_STORAGE`，属于 Google 的受限权限，而 `READ_EXTERNAL_STORAGE` 在 Android 13 之后已经失效。

`flutter_markdown` 已被官方归档，升级 Flutter 之前要先评估替换方案。`packages/workmanager/` 是对 workmanager 0.5.2 的 Kotlin 本地修改，官方新版稳定后应该换掉。

笔记文件全程只读，App 不会写回或修改 vault 里的任何 `.md`。

## 文档

`AGENTS.md` 记了架构决策、几个踩过的坑（`FutureProvider` 的同步读取、`copyWith` 的哨兵值、流式解析的切分边界）和待办事项；`docs/superpowers/` 下是最初的设计文档和实现计划。
