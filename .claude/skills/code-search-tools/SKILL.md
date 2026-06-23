# Skill: Code Search Tools

Use this skill when exploring or navigating the pocketclaw codebase.

## Tool Priority

1. **semble first** — semantic search, finds by intent not exact string
2. **grep second** — for exact strings, method names, type names
3. **Read third** — only after you know the exact file and need full context

## semble

```bash
# Find where GemmaService.generate is called
semble search "inference generate call" . 

# Find RAG retrieval logic
semble search "retrieve chunks RAG context" .

# Find error handling for model loading
semble search "model loading error state" .

# Find Hive box initialization
semble search "Hive openBox init" .

# Search docs only
semble search "context compaction" . --content docs

# Search config
semble search "embedder URL gecko" . --content config
```

Or via MCP in Claude Code:
```
mcp__semble__search("inference generate call", repo=".")
mcp__semble__find_related(file_path="lib/services/gemma_service.dart", line=416, repo=".")
```

## grep — Exact Symbol Search

```bash
# Find all callers of a method
grep -rn "\.generate(" lib/

# Find all ValueListenableBuilder usages
grep -rn "ValueListenableBuilder" lib/

# Find all GemmaState usages
grep -rn "GemmaState\." lib/

# Find all dispose() implementations
grep -rn "void dispose" lib/

# Find inline colors (violations)
grep -rn "Color(0xFF" lib/
```

## Key File Locations

| What | Where |
|---|---|
| Theme tokens | `lib/core/pocketclaw_theme.dart` |
| Model config | `lib/core/constants/gemma_config.dart` |
| App init + service init order | `lib/main.dart:470-490` |
| Gemma inference | `lib/services/gemma_service.dart:416` |
| RAG indexing | `lib/services/rag_service.dart:170` |
| RAG retrieval | `lib/services/rag_service.dart:250` |
| Device actions | `lib/services/device_actions_service.dart` |
| Intent parsing | `lib/services/chat_command_service.dart` |
| Main chat UI | `lib/screens/chat_screen.dart` |
| Voice capture | `lib/services/voice_service.dart:255` |

## flutter analyze

After any edit:
```bash
flutter analyze
```

Expected: `No issues found!`

If there are warnings: fix before moving on. Common fixes:
- `dart fix --apply` — auto-adds missing `const`, fixes minor style issues
- `dart format lib/` — fixes formatting
