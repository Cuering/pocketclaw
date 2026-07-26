# PocketClaw v1.1.0（中文界面）

## 变更
- **默认中文界面**：引导、对话、技能、工作流、会话列表、设置抽屉、诊断页、悬浮窗等 UI 文案中文化
- Android 无障碍服务描述中文
- 修复 DeviceActionsService 标识符误改导致的编译失败
- 版本：`1.1.0+2`

## 安装
1. 下载 `app-release.apk`（arm64-v8a）
2. 首次启动下载 Gemma 4 E2B + Gecko（约 1.6 GB，建议 Wi‑Fi）
3. 授予需要的权限后即可离线使用

## 构建
```bash
flutter pub get
flutter build apk --release
```
