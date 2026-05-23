created flutter start app, up and running, used claude for idea and brainstorming, i demanded claude for clean arxhitecture like launch.json,flavors, business layer other layer based, abstract classes, methods etc.,  claude recommended me, we dont have to follow uncle bob style(clean architecture), because  we have less time left and we should accomplish our goal within given time.

So finally created starterproject(just using flutter create, nothing else), created git repo, made it public, added mit licence, readme and pushed to dev.

a small shift, i didnt read properly what claude was asking me to do, i mean it tried to minimize the requirements, but after mutual communication we settled for function calling, overlay, screenshot explaination, screen overlay, screen capture and q n a, 

## May 13 — late night

okay so today was a lot.

started full day on flutter_gemma — got the project scaffold up, service
layer written, all clean code, smoke test passing. felt good.

then everything broke. install kept timing out on the emulator. spent
ages thinking it was a network issue, then realized android emulator
NAT is just bad at large downloads — every time it would die at 40-ish
percent and restart from zero because hugging face cdn doesn't resume
properly.

switched to the nord ce 4 finally (kept putting it off, kept poking at
emulator instead). once usb debugging was set up properly, model
downloaded in like a minute over office wifi. **2.4 gb in under a
minute**, no retries, perfect. that was the moment things started
moving. nord = real progress.

then hit the actual wall: load() kept throwing 
"is a LiteRT-LM model — should be handled by Dart FFI" error.

we tried EVERYTHING:
- rolled back the plugin version (twice). same error.
- tried different ModelType enums. same error.
- pushed the file manually with adb. fought with SELinux. eventually
  got it pushed (cat | adb shell run-as tee — chef's kiss). still same
  error.
- tried fromFile() instead of fromNetwork(). same error.

claude was getting tired and started giving me wrong version numbers
and hallucinating APIs that didn't exist. me, half asleep, kept going
anyway because i wanted to see it work tonight.

finally i opened the actual flutter_gemma source code in ~/.pub-cache
because docs and AI both seemed to be lying. claude asked me to grep
the source. **and there it was.** the bug was 1 missing named param.

`installModel()` defaults fileType to ModelFileType.task. our file is
.litertlm. we never passed fileType, so the plugin thought it was a
.task file and tried to load it through the wrong kotlin engine,
which then threw because it could tell from the bytes that the file
was actually .litertlm. circular self-aware bug. one line fix.

added `fileType: ModelFileType.litertlm` to installModel(). tapped
install on the nord. tapped load. tapped generate. **gemma responded.**

ON. MY. PHONE. OFFLINE. real gemma 4. real text out.

biggest lesson tonight: when a library bug confuses you, read the
library source on disk. don't trust google. don't trust AI summaries.
the source code on your machine is the only thing that's actually true
for your version.

second lesson: sleep is a debugging tool. half the wrong turns tonight
came after midnight. should have stopped at 11 and finished this in
20 minutes tomorrow morning. ah well.

okay. sleeping. day 3 we do the actual UI.

## May 16 — evening

came back today after a day off (yesterday was nothing). app was technically
working but slow as hell for anything beyond "hi". simple prompts = 2-5 sec,
"write a python function" = 5+ minutes and got cut mid-sentence. felt broken.

claude wanted to check whether GPU was even kicking in. turned out yes —
all 2068+ inference nodes were delegated to OpenCL / adreno. so it wasn't
a "secretly running on CPU" problem. the slowness was just **the model
writing essays** because we asked for max 2048 tokens with no streaming and
no system prompt telling it to be concise.

three fixes:

1. **streaming**. instead of waiting for the entire response then dumping
   it, now tokens appear one at a time as gemma generates them. same total
   time but feels like 10x faster because you're not staring at a frozen
   screen.

2. **maxTokens 2048 → 1024**. mostly safety net. real fix is the prompt.

3. **system prompt**. this was the interesting one. first attempt was
   rule-based: "answer in 1-3 paragraphs, give one code example not three."
   tested with python prompt — went from 1001 tokens to 132. amazing.
   then i tried the SAME python prompt again ("three implementations").
   it gave me ONE. because of my literal "not three" rule. lol.

claude pushed back: "good system prompts describe character, not rules."
that's a nice line. rewrote it to be about *how the assistant should
think* — match length to question, no preambles, no restating the
question, say "i don't know" instead of padding when unsure. the model
adapts per-prompt now. same "three implementations" prompt: 256 tokens,
3 clean function defs, no fluff. 29 seconds, 8.5 tok/s.

big takeaway: when you write a rule for one annoying case, you've also
written a rule that fights the model on every case the rule doesn't fit.
character > rules.

next: image input. claude wants me to find a hindi/kannada document photo
for the demo story. multilingual ocr on-device is the actual cool thing.


## May 16 — late evening, continued

after the streaming + prompt commit, kept going and got multimodal working.
gemma can SEE images now. ✨

added image_picker package, manifest permissions, an Attach button, thumbnail
UI, and routed the image bytes through to Message.withImage() in the service
layer. analyze was clean. ran it. attached a photo. asked "what's in this
image?". gemma replied **"please provide the image."**

bruh.

felt like ground hog day after the day 2 .litertlm bug. exact same vibe:
plugin sees the message, debug logs look fine, no error, but the model
clearly didn't see anything.

claude wanted to grep the plugin source AGAIN. fair, last time it worked.

`grep -rn "supportImage" ~/.pub-cache/...`

and there it was. flutter_gemma's addQueryChunk has a flag `supportImage`
that defaults to FALSE. if you don't pass `supportImage: true` when
loading the model, the plugin silently drops your image bytes before
they ever reach the vision encoder. only the text goes through.

THIS IS EXACTLY THE SAME BUG AS DAY 2. a "support X" / "with X" /
"X file type" default parameter that defaults to something wrong for
our case, no error, no warning, just silently degraded behavior. you
have to grep the library source to find these. the docs don't mention them.
even the examples don't always show them.

claude added this to its "debugging library bugs" playbook:
**when feature X doesn't work, grep for "support" + X or "enable" + X or
"with" + X parameters. defaults are where silent failures hide.**

set `supportImage: true` + `maxNumImages: 1` in load(). load now takes
10-12s instead of 7 (vision encoder loads too). re-ran. attached a
photo. asked the same question. gemma described what was in it.

✨ ON-DEVICE GEMMA 4 VISION ✨ on a $250 phone in india. offline.

took a screen recording for the demo video later. also realized: the
two big bugs (day 2 routing + today's vision flag) are both **the same
pattern** — silent defaults in a library that don't fit your case. lesson
i actually internalized now: when stuck, GREP THE LIBRARY SOURCE FIRST.

calling it for the night. tomorrow: floating overlay bubble. that's
android system_alert_window territory which is supposedly a permission
nightmare. fresh brain only.

## May 17 — evening

day 4. overlay bubble.

started the day with claude pulling me up on scope. literally first
clarifying question and i was already trying to add chat UI on top of
overlay work. she called the pattern out — day 1 scope debates, day 2
scope debates, day 3 end "i promise i won't bring this up again",
day 4 first task: i'm bringing it up again. ouch but fair.

picked "just the overlay today, UI waits till day 6." stuck with it.

did the work. flutter_overlay_window 0.5.0, manifest changes for
SYSTEM_ALERT_WINDOW + FOREGROUND_SERVICE_SPECIAL_USE + registered the
overlay service. one of those special-use permissions where google
literally reads your justification text during play store review.
claude wrote me a specific honest one instead of the docs placeholder.

dart side: the cool thing today is `@pragma("vm:entry-point")`.
the overlay runs in a SECOND DART ISOLATE. separate VM. cannot see
my GemmaService singleton. literally a different program that happens
to share the same APK. blew my mind a little. communication will be
SendPort message passing tomorrow.

dropped in overlayMain() + _ClawBubble (just an indigo circle with a
🐾 paw print for now), wired up 2 buttons (show / hide), tested:

1. tap show overlay
2. android opened "display over other apps" settings
3. toggled pocketclaw on
4. came back, tapped show overlay again
5. **indigo bubble appeared, dragged it around, opened other apps,
   bubble STILL THERE OVER WHATSAPP** 🎯
6. tap hide, cleanup, done.

took about an hour of actual coding. clean. no drama. no plugin bugs
to grep through. felt easy compared to day 2-3.

claude pointed out: 4 of 8 technical risks done. remaining 4 are
"integration + flutter UI" not "fight a native plugin." curve is
flattening.

biggest lesson today wasn't technical, it was the scope thing. i keep
wanting to do more than the task. tomorrow it'll happen again. the
goal isn't to fight it — the goal is to notice it before i spend an
hour following it.

tomorrow: cross-isolate comms (SendPort between bubble and main app)
+ screen capture via MediaProjection. that's the killer feature —
tap bubble → grab screen → gemma describes it. that's THE demo moment.

## may 17 — late evening

day 5 stub. didn't ship the milestone.

goal was: tap bubble → main app reacts. we got: tap bubble → ¯\_(ツ)_/¯

flutter_overlay_window's `shareData` from overlay side fires fine. main
app's `overlayListener.listen` never receives. found a 9-month-old open
github issue with identical symptoms. zero maintainer replies. plugin
is dead.

tried the fork (`_plus`) — looked promising but turns out it's
architecturally only built for main → overlay messaging. wrong direction.
useless to us.

briefly tried using `AppLifecycleState.resumed` as a signal (saw it in
my logs and got excited) — turns out tapping the bubble doesn't actually
cause that. just normal app foregrounding does. red herring.

ALSO: i tried to push past this multiple times. "let's just read the
docs again." "let's just keep going." "no time cap, we fix it tonight."
claude pushed back every time, finally said "i'm pulling rank gently:
stop, the data is telling you something." and i actually listened.
that's progress on a pattern that's been hurting me all week.

tomorrow: write native kotlin myself. methodchannel from inside the
overlay → through our own bridge → into the main app's dart handler.
no plugin's broken kotlin between us and the message. it'll be ~2 hours
of kotlin in the morning. then screen capture on top of it.

biggest realization tonight: not all bugs are grep-and-fix. day 2 and
day 3 were "library has a parameter we didn't pass." this was "the
library's native code is broken and there's no parameter to add." different
category. stopping fast on category 2 was the right call.

it's 8 PM. i'm gonna eat. day 4 commit going up clean. day 5 starts
fresh tomorrow.



Here you go. This one's for you, not the repo.

---

# Personal Journal — Mon May 18, 2026

Today was day 5b. Started with a real win, ended in a debugging hole. Let me write down what actually happened so future-me can read it without sugar-coating.

## What I did right

I found the IsolateNameServer workaround for `flutter_overlay_window` by myself, at midnight, by reading GitHub issue #22 carefully. The maintainer of the broken plugin had literally posted the workaround himself months ago and I was the one who dug it out. Implemented it in ~40 lines of Dart this afternoon. Pushed clean. That's Day 5a.

That single commit moved the project from "fundamentally blocked on overlay→main IPC" to "working end-to-end." The whole day after that was bonus. I should remember the feeling.

## What I did wrong

I had a 30-minute cap on the screen capture work. I blew it. Then I blew the next cap. Then I blew the cap after that. By the time I was patching the third plugin's Kotlin at 9:30 PM, I was in exactly the same anti-pattern as yesterday — "just one more thing, this one will work."

Claude kept gently flagging it. I kept overriding. Some of the overrides were right (the IsolateNameServer one paid off massively), but most weren't. The honest accounting:

- Plugin 1 archaeology: 60 min, dead end
- Plugin 2 patches (namespace, Android 14 callback): 45 min, made it compile, didn't make it work right
- Kotlin instrumentation and logcat tailing: 45 min, gave us the diagnosis
- Total time spent: ~3+ hours
- Working screen capture: NO. The plugin captures the permission dialog, not the actual screen.

The pattern: I confused "we're making progress" (each tap reveals a new bug) with "we're solving the problem" (we have a working screenshot). We weren't. The plugin is fundamentally broken on Android 14 and patching it layer by layer is treating symptoms.

## What I actually learned tonight

About Android:
- MediaProjection on Android 14 is single-use by default. Real apps keep the projection alive in a long-running foreground service.
- `MediaProjection.Callback` must be registered before `createVirtualDisplay` (this killed plugin #2)
- Plugin-side `void requestMediaProjection()` has no awaitable signal back to Dart, which is why all the timing races exist
- The `setOnImageAvailableListener` fires on the first frame, which is whatever was on screen during the permission dialog transition

About my own process:
- I keep saying "I can't write Kotlin" and using that as a reason to chase plugin solutions
- Three different plugins now have proven that the plugin ecosystem hasn't caught up to Android 14
- The realistic path forward is either (a) write the 150 lines of Kotlin with Claude's help, or (b) give up on MediaProjection and use system-screenshot pickup as a substitute
- "Can't write Kotlin" is a story I've been telling myself. Reading and patching 200 lines of it tonight without dying suggests the story may be wrong.

About my own stamina:
- I get more stubborn the later it gets, not less
- The "I'll stop when I'm tired" framing is true but it's also how I justify pushing past my own caps
- A cap I set at 8:25 PM is a contract with my better-rested self at 8:25 PM. Future-me at 9:45 PM is not authorized to renegotiate it.
- Yesterday's late-night rabbit hole and tonight's screen-capture grind have the same shape. I should notice the shape.

## What I want to do differently

This isn't a beat-myself-up section. Just a list:

1. When I set a cap, treat it as a real cap. The "I'll stop when tired" framing is a loophole.
2. When Claude flags "this is the same pattern as yesterday," that's signal, not pessimism. He doesn't actually want me to stop — he wants me to stop *spending energy on the wrong thing*. There's a real difference.
3. Stop saying "I can't write Kotlin." Say "I haven't written Kotlin yet." We have 5 working days. Tomorrow we either write the Kotlin together or we change strategy. Both are fine.
4. Remember tonight's actual win: Day 5a. That was the hard one. I solved it. Everything else tonight was a side quest that didn't need to be tonight.

## What's actually shipped this week

- Day 1-2: Gemma loads, generates, streams (with vision)
- Day 3a: Streaming + adaptive system prompt + perf tuning
- Day 3b: Multimodal vision end-to-end on Nord
- Day 4: Floating overlay bubble draggable
- Day 5a: Bubble→main IPC via IsolateNameServer ✅ (today's real win)
- Day 5b: Screen capture works at the bitmap level but captures the wrong frame ⚠️

That's a lot. The contest demo doesn't need everything tonight. It needs a 90-second video on Saturday.

## Plan for tomorrow

Open with one of two paths:

**Path 1 — Write own Kotlin MediaProjection service.** ~150 lines, 2-3 hours, fresh head, with Claude drafting. Solves the capture-the-right-frame problem properly.

**Path 2 — Use system-screenshot pickup.** User takes a native screenshot with volume-down + power, then taps the bubble, PocketClaw auto-picks up the most recent screenshot from the gallery. No MediaProjection. Demo is "Take a screenshot, then summon Claw to explain it."

Both are valid. Sleep on it. Whichever feels right at 9 AM is the one.

## One thing to remember

The fact that the bubble works, screen-shot works (mostly), multimodal Gemma works, all on a Nord CE 4 in India, in 5 days, alone, while learning Flutter as I go — that's not nothing. Most people would not have shipped this much in this time.

Tonight had a hole. Don't carry the hole into tomorrow.

Sleep.

---

