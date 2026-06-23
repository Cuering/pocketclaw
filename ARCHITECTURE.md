# PocketClaw — Architecture

> Read this before starting any task. It is the system map.

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Screens (lib/screens/)                                      │
│  chat_screen.dart · conversation_list_screen.dart           │
│  onboarding_screen.dart · diagnostics_screen.dart           │
└───────────────────┬─────────────────────────────────────────┘
                    │ calls singleton .instance methods
┌───────────────────▼─────────────────────────────────────────┐
│  Services (lib/services/)                                    │
│  GemmaService  RagService  VoiceService                      │
│  DeviceActionsService  ChatCommandService                    │
│  ConversationStore  DocumentStore  PrefsService              │
│  OverlayControllerService  ConnectivityService               │
└──────┬────────────┬───────────────────────────┬─────────────┘
       │            │                           │
┌──────▼──────┐  ┌──▼──────────────┐  ┌────────▼────────────┐
│  Models     │  │  Hive Boxes     │  │  Native Layer       │
│  (lib/models│  │  conversations  │  │  flutter_gemma      │
│  Conversation  │  documents      │  │  speech_to_text     │
│  Document   │  │  (local SQLite) │  │  MethodChannel      │
│  Message    │  └─────────────────┘  │  pocketclaw/device  │
│  UserPrefs) │                       └─────────────────────┘
└─────────────┘
```

## Isolate Architecture

The app runs in **one active isolate** (main). A second isolate (overlay) is
scaffolded but inactive — all overlay code is commented out pending
`FlutterOverlayWindow` integration.

- **Main isolate:** UI + Gemma inference + all services
- **Overlay isolate (`overlayMain`):** Floating bubble — commented out

## Service Init Sequence (main.dart)

```dart
await ConversationStore.instance.init();   // Hive box for chats
await DocumentStore.instance.init();       // Hive box for RAG doc metadata
await PrefsService.instance.init();        // SharedPreferences wrapper
await GemmaService.instance.init();        // Detects installed/not installed
RagService.instance.init();               // sqlite-vec store (fire-and-forget)
// VoiceService init is lazy — called from onboarding or chat
```

## Key Service APIs

### GemmaService
```dart
GemmaService.instance.state           // ValueListenable<GemmaState>
GemmaService.instance.embedderState   // ValueListenable<EmbedderState>
GemmaService.instance.downloadProgress // ValueListenable<int> (0–100)
GemmaService.instance.lastError       // Object?
await GemmaService.instance.ensureInstalled()
await GemmaService.instance.ensureLoaded()
await GemmaService.instance.generate(prompt, imageBytes: bytes, onToken: cb)
await GemmaService.instance.installEmbedder()
await GemmaService.instance.getEmbedder()   // returns EmbeddingModel
await GemmaService.instance.dispose()
```

### RagService
```dart
RagService.instance.state             // ValueListenable<RagState>
await RagService.instance.indexDocument(text: t, name: n, conversationId: id)
await RagService.instance.retrieve(query: q, conversationId: id)
await RagService.instance.getDocStarts(conversationId: id)
await RagService.instance.deleteDocument(doc)
RagService.instance.chunk(text)       // List<String>
```

### VoiceService
```dart
VoiceService.instance.state           // VoiceState (not ValueListenable)
VoiceService.instance.addListener(fn)
VoiceService.instance.removeListener(fn)
await VoiceService.instance.init()
await VoiceService.instance.triggerManualVoiceCapture()
```

### DeviceActionsService
```dart
await DeviceActionsService.instance.setTorch(bool)
await DeviceActionsService.instance.openDialer(phone)
await DeviceActionsService.instance.openSms(phone, body)
await DeviceActionsService.instance.openCalendar(title: t, dateTime: dt)
await DeviceActionsService.instance.openAlarm(label: l, hour: h, minute: m)
await DeviceActionsService.instance.openWebSearch(query)
await DeviceActionsService.instance.sendNotification(title, body)
// All return DeviceActionResult(ok: bool, message: String)
```

### ChatCommandService
```dart
await ChatCommandService.instance.tryHandleWithGemma(text) // String?
await ChatCommandService.instance.tryHandle(text)          // String?
// Returns null if not a device command; returns reply string if handled
```

## Feature Inventory

| Screen | File | State source |
|---|---|---|
| Chat | `chat_screen.dart` | GemmaService + ConversationStore (ValueListenable) |
| Conversation list | `conversation_list_screen.dart` | ConversationStore |
| Onboarding | `onboarding_screen.dart` | PrefsService |
| Diagnostics | `diagnostics_screen.dart` | GemmaService + RagService state |

## Routing

Simple `Navigator` — no go_router. Entry screen determined in `main.dart`:
```dart
if (PrefsService.instance.isOnboarded) → ChatScreen
else → OnboardingScreen
```
Navigation between screens uses `Navigator.push` / `Navigator.pop`.

## Design System

`lib/core/pocketclaw_theme.dart` — neobrutalism dark theme.
Colors: `bg`, `bg2`, `bg3`, `cyan`, `purple`, `mint`, `text`, `text2`,
`muted`, `warning`, `error`, `ink`.
Shadow: `hardShadow` (5,5 offset, 0 blur, ink color).
Border: `hardBorder([color, width])` — default cyan, 2px.
Panel: `panel({color, border, radius, shadow})` — standard card decoration.
