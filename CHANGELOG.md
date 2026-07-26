## 1.1.0 — 2026-07-26

- 默认中文界面（引导 / 聊天 / 技能 / 工作流 / 悬浮窗）
- Android 无障碍说明中文
- 版本号 1.1.0+2

# PocketClaw — Changelog

> Append-only. One entry per shipped unit of work. Format: `## YYYY-MM-DD — What shipped`

## 2026-06-23 — Claude config setup

Added `.claude/` configuration: CLAUDE.md, rules (gemma, rag, hive, services,
widgets, theme, performance, voice), skills (gemma-patterns, rag-patterns,
device-actions-patterns, screen-checklist, smart-commit, code-search-tools),
commands (new-screen, new-service, pr-review), and flutter-reviewer agent.
Relay docs added: ARCHITECTURE.md, DECISIONS.md, CHANGELOG.md, ERRORS.md.

## 2026-05-XX — Contest submission (Google Gemma 4 Challenge)

Shipped: on-device chat (Gemma 4 E2B INT4), multimodal vision (image analysis),
RAG document Q&A (Gecko 110M + sqlite-vec), device actions via natural language
(flashlight, alarms, SMS, calendar, dialer, notifications), persistent chat
history (Hive), context compaction, press-hold voice input (system STT),
neobrutalism dark theme, onboarding flow, diagnostics screen.
