# 📖 To-Do Book — Implementation Plan (STP v2.1)

## 1. What you asked for

1. A **To-Do Book** becomes the **first tab**. It looks and feels like a real diary: one **page per day**, today's page opens first.
2. On a page you **add subjects** — only from subjects you already created — and set **how long to study each one that day**.
3. The old **Today** screen moves to the **second tab**.
4. **A timer can't start without a task.** You first pick one of today's tasks in the book; after that only *that* subject's timer can start (any chapter of it, or general study).
5. When the task's target is reached, the **stopwatch stops by itself** and an **alarm rings** — it keeps ringing until you press **Stop**.

## 2. Book design ("make it feel like a book")

| Element | Detail |
|---|---|
| Cover | Leather-style cover with your name opens with a 3D swing the first time you open the tab each launch. |
| Pages | Cream paper, ruled lines, red margin, spiral binding holes, page number footer, serif "ink" typography. |
| Page turns | Swipe left/right: pages rotate in 3D around the spine with a shadow, like a real page turn. |
| Ribbon | A red bookmark ribbon hangs on today's page; a "Today" button jumps back to it. |
| Tasks | Handwritten-style lines: subject emoji, name, "2h 30m" target, highlighter-style progress fill, ✓ tick when done. |
| Stamps | Past pages get rubber stamps: **DAY CONQUERED** (all done), **PARTLY DONE**, **MISSED**. |
| Stickers | Gold ⭐ sticker on a page when every task is finished. |
| Sticky note | Yellow sticky note for the day's reflection + mood row 😫 😕 😐 🙂 🤩. |
| Calendar jump | Tap the date to jump to any page. |

### Extra ideas (mine)
- **Plan ahead:** future pages are editable, so you can plan tomorrow tonight.
- **Carry over:** today's page offers to copy yesterday's unfinished tasks with their remaining time.
- **Past pages are read-only history** — you can't rewrite the past, only look at it.
- **"+15 min" snooze-style extend** on the alarm screen and on finished tasks, so you can keep going.
- **Page score:** "3/4 done · 82%" in the page header.
- **Live link:** the running task pulses on the page and the Today/Focus screens show "x min left".

## 3. Data model

```dart
class PlanTask { String id; String subjectId; int targetMs; }
class DayPlan  { String dayKey; List<PlanTask> tasks; String note; int? mood; }
AppData {
  Map<String, DayPlan> plans;     // key = study-day key (5 AM reset)
  String? selectedTaskId;         // today's chosen task
  String? selectedTaskDay;        // the day it belongs to
  AlarmState? alarm;              // ringing alarm (survives restarts)
}
```

- **Progress** of a task = all time studied for that subject on that study day (timer, Pomodoro and manual sessions).
- A task is **done** when progress ≥ target.
- One subject can appear **once per page** (adding it again is refused; edit its time instead).

## 4. Rules in `StudyStore`

| Action | Rule |
|---|---|
| `addPlanTask(day, subject, target)` | subject must exist · target 1 min – 24 h · not a past day · no duplicate subject |
| `updatePlanTaskTarget` | same limits; lowering it below progress completes the task (and stops/rings a running timer) |
| `removePlanTask` | past days refused; if it's the selected task → its timer stops and the selection clears |
| `selectTask(id)` | only today's tasks · not already done · switching stops a timer running for another subject |
| `startTimer / startPomodoro / toggleTimer` | return a `StartGate`: `ok`, `noTaskSelected`, `wrongSubject`, `targetReached` |
| tick / app resume | if a running timer reaches the target → session is saved **ending exactly at the target moment** (no overshoot even if the app was closed), timer + Pomodoro stop, alarm rings |
| day reset (5 AM) | a running timer stops at the boundary; yesterday's selection is cleared |
| `stopAlarm()` | stops ringing, cancels the notification |
| `extendSelected(min)` | adds minutes to the task, stops the alarm, ready to start again |
| delete subject | its tasks are removed from every page |
| Pomodoro | break time doesn't count; target reached in a focus block ends the whole Pomodoro |

## 5. Alarm

- `flutter_local_notifications`: a notification is **scheduled at the exact moment** the target will be reached when a timer starts, and cancelled/rescheduled on stop, pause or edits. This rings even if the app is closed or the phone is locked.
- Channel uses the **alarm audio stream**, a custom generated chime (`res/raw/alarm.wav`), vibration, full-screen intent and Android's **insistent flag** → it loops until stopped. Notification has a **Stop** action.
- In the app, a full-screen **ringing page** (shaking bell, subject, time studied) with a big **STOP** button and **+15 min**.
- Permissions: notifications (asked on first task start), exact alarms (`USE_EXACT_ALARM`), full-screen intent, boot receiver to survive restarts.
- Alarm logic is behind an `AlarmScheduler` interface so tests use a fake.

## 6. Navigation

`Book · Today · Focus · Insights · Ranks · Profile` (labels shown for the selected tab to fit six).
- **Today:** play buttons only work for the selected task's subject; others show a 🔒 and a message with a "Open book" shortcut. The hero card shows the selected task and time left.
- **Focus:** subject is locked to the selected task; without a task it shows "Pick a task in your book".

## 7. Tests (`test/todo_book_test.dart`)

Store tests run with a **fake clock**, **in-memory storage** and a **fake alarm scheduler**:

- adding: valid · unknown subject · zero/negative/over-24h target · duplicate subject · past day refused · future day allowed
- selecting: today only · future/past refused · done task refused · switching stops other subject's timer
- gate: no task · wrong subject · right subject (any chapter) · target reached · stopping always allowed
- auto-stop: exact end time · progress counts earlier sessions + manual sessions · app "closed" past the target (no overshoot) · alarm scheduled at the right moment, cancelled on manual stop
- edits: lowering target below progress while running → stops + rings · raising target · removing selected running task
- alarm: stop clears it · extend adds time and allows restart · alarm survives a store reload
- Pomodoro: target reached inside a focus block ends Pomodoro · break doesn't count · gate applies
- day rollover: timer stops at 5 AM boundary · selection cleared · new day needs a new pick
- delete subject removes tasks & selection · carry-over copies only unfinished tasks with remaining time · past page status (done / partial / missed)
- persistence: plans round-trip through JSON; old backups without plans still load

Plus widget tests: the book opens on today's page and adding a task through the sheet shows it on the page.
