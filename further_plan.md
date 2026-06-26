Addition 1 — Primitive Engine (Very Important)

Currently:

Skill
↓
Accessibility

Instead introduce:

Skill
↓
Primitive Engine
↓
Accessibility

Primitives:

Read Screen
Read Notification
Read Clipboard
Read File
Take Screenshot

Open App
Tap
Type
Scroll
Swipe
Back

Store Memory
Search Memory

Render Component
Create Workflow

Reason:

Pi and OpenClaw succeed because they expose primitives, not features.

Then skills become combinations of primitives.


---

Addition 2 — Workflow Engine

This is the biggest thing missing.

Current:

User
↓
Skill
↓
Execute

Add:

Workflow

Example:

When PDF arrives
↓
Extract text
↓
Summarize
↓
Create flashcards
↓
Notify me

Saved forever.


---

PocketClaw should support:

{
  "trigger":"pdf_received",
  "steps":[]
}

This is basically local Zapier/IFTTT.


---

Addition 3 — Skill Marketplace

Not for v1.

But architecture should support it.

Skill format:

{
  "name":"Exam Preparation",
  "version":"1.0",
  "steps":[]
}

Export:

study.pcskill

Import later.


---

This becomes:

PocketClaw Community

instead of only:

PocketClaw App


---

Addition 4 — Long Running Agent Tasks

Current:

User asks
↓
Response

Add:

Background Agent Jobs

Example:

Track my flight

PocketClaw:

Creates task
↓
Runs later
↓
Notifies user


---

Example:

Remind me if any invoice remains unpaid.

Not instant.

Persistent.


---

This comes directly from OpenClaw.


---

Addition 5 — Agent Loop

Current:

Think Once
↓
Act Once

Upgrade:

Observe
↓
Plan
↓
Act
↓
Observe
↓
Act
↓
Finish

Example:

Book my coffee

Agent:

Open Swiggy
↓
Observe Screen
↓
Search
↓
Observe
↓
Add To Cart
↓
Observe
↓
Done

This is what separates assistants from agents.


---

New Architecture

Replace:

Wake Word
↓
Overlay
↓
Context Engine
↓
Gemma
↓
Skill Engine
↓
Tool Executor
↓
Accessibility Executor
↓
Dynamic UI Renderer

with:

Wake Word
↓
Overlay
↓
Context Engine
↓
Memory Engine
↓
Gemma
↓
Skill Engine
↓
Workflow Engine
↓
Primitive Engine
↓
Agent Loop
↓
Tool Executor
↓
Accessibility Executor
↓
Dynamic UI Renderer


---

Memory Engine Upgrade

Current memory section is too small.

Split into:

Episodic Memory

Past conversations
Past actions
Past workflows


---

Preference Memory

Favorite coffee
Preferred food app
Study style


---

Semantic Memory

Facts user wants remembered


---

Skill Memory

Generated skills
Skill usage frequency


---

Future Fine-Tuning Update

Add:

Fine Tune #5

Workflow Generation

Input:

When I receive invoices summarize them.

Output:

{
  "trigger":"invoice_received",
  "steps":[]
}


---

Fine Tune #6

Primitive Selection

Input:

Order my coffee.

Output:

{
  "primitives":[
    "open_app",
    "tap",
    "type"
  ]
}


---

Updated Product Positioning

Replace:

PocketClaw is a Local AI Operating System for Android.

with:

PocketClaw is a Private Local Agent Operating System for Android that creates, remembers, executes and evolves skills and workflows using on-device AI.


---

My priority order now

If I were building tomorrow:

Phase 1

Overlay

Context Engine

Primitive Engine

Accessibility


Phase 2

Skill DSL

Skill Registry

Skill Generation


Phase 3

Workflow Engine

Long Running Tasks


Phase 4

Dynamic Components

Skill Marketplace


Phase 5

Fine-tuning:

Tool Calling

Skill Routing

Memory Extraction

Skill Generation

Workflow Generation

Primitive Selection
