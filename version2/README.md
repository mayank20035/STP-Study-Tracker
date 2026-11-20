<p align="center"><img src="screenshots/icon.png" width="128" alt="STP v2 icon"></p>

# 🚀 STP v2 — Study Tracker (Flutter)

Version 2 of **STP**, rebuilt from scratch in **Flutter / Material 3**.

## 📖 New in v2.1 — the To-Do Book

| Today's page | A finished day | Target reached | Task done |
|:---:|:---:|:---:|:---:|
| <img src="screenshots/book_today.jpg" width="180"> | <img src="screenshots/book_yesterday.jpg" width="180"> | <img src="screenshots/alarm.jpg" width="180"> | <img src="screenshots/book_done.jpg" width="180"> |

The app now opens on a **diary**. Every page is one day, and today's page opens first.

1. **Plan:** on a page, tap *Add subject…*, choose one of your subjects and set how long to study it (e.g. Physics 2h, Maths 1h 30m).
2. **Pick:** tap a subject on today's page. Only then does its timer unlock, on the book page itself, on **Today** and on **Focus**. Every other subject shows a 🔒.
3. **Study:** start the stopwatch or a Pomodoro. The book shows a live "time left" countdown with a highlighter-style progress bar.
4. **Alarm:** when the target is reached, the timer **stops by itself** at the exact second and an **alarm rings until you press STOP**. This also works when the app is closed or the phone is locked, because the alarm is scheduled as a notification with a custom chime, vibration and a lock-screen alert. There's also *Stop & keep going +15 min*.

Book touches:
- a leather cover that swings open when you start the app
- 3D page-turn swipes
- ruled paper, a spiral binding and a red bookmark ribbon on today's page
- **DAY CONQUERED / PARTLY DONE / MISSED** rubber stamps and a ⭐ on finished days
- a sticky note with a mood picker
- plan future days ahead, and carry over yesterday's unfinished tasks with their remaining time
- past pages are read-only history

Details and the edge-case rules are in [TODO_BOOK_PLAN.md](TODO_BOOK_PLAN.md).

| Today | Focus | Insights | Ranks | Profile |
|:---:|:---:|:---:|:---:|:---:|
| <img src="screenshots/today.jpg" width="160"> | <img src="screenshots/focus.jpg" width="160"> | <img src="screenshots/insights.jpg" width="160"> | <img src="screenshots/ranks.jpg" width="160"> | <img src="screenshots/profile.jpg" width="160"> |

*The icon: a stopwatch whose ring fills from white to gold as you study, wrapped around an open book with a golden "aha" spark.*
The original React Native app (v1) lives in the repository root on the `main` branch and is untouched.

📥 **Download the APK:** see the [latest release (v2.1.0)](https://github.com/mayank20035/STP-Study-Tracker/releases/tag/v2.1.0).
- `STP-v2.1.0-arm64.apk` (~20 MB) works on almost every modern Android phone.
- `STP-v2.1.0-universal.apk` (~55 MB) works on any device.

The first time you start a timer, allow notifications so the target alarm can ring.

It installs **alongside** v1 (different package id: `com.mayank.stp_v2`). Android will ask you to allow installing from unknown sources.

## ✨ Everything else in v2

| | Feature |
|---|---|
| 🎯 | **Focus mode** — full-screen timer with a progress ring. Stopwatch **or Pomodoro** (custom focus / break lengths, long breaks, auto-start). |
| 🔥 | **Streaks** — current & longest streak with a configurable daily minimum. |
| ⭕ | **Daily goal ring** on the Today dashboard. |
| 🟩 | **GitHub-style heatmap** (26 weeks) + month calendar; tap any day for a subject/chapter breakdown. |
| 📊 | **Insights** — week / month / year bar charts with average line, subject split donut, *when you study* hour chart. |
| 🧠 | **Smart insights** — peak hour, best weekday, week-over-week change, neglected subjects, average session length. |
| 🏅 | **19 achievements** (Night Owl, Marathon, 100 Hour Club, Pomodoro Pro …) with unlock celebration. |
| ⭐ | **XP & levels** — 1 XP per minute, titles from *Novice* to *Legend*. |
| 🏆 | **Leaderboard** — subjects / categories / chapters, *all-time / this week / today*, podium, Hall of Fame. |
| ✅ | **Syllabus tracking** — tick chapters as complete. |
| 🗒️ | **Session log** — every session is stored; edit, delete (with undo) or add a forgotten session manually. |
| 🎨 | Subject emoji + colour, 6 accent colours, light / dark / system theme, emoji avatars. |
| 🔁 | **Imports v1 backups** (`STP_Backup.json`) — your old data comes with you. |

## 🐛 v1 issues fixed

- History was deleted after 30 days → v2 keeps everything.
- Charts used UTC dates while timers used local dates → one consistent "study day" (default reset 5 AM, configurable).
- Sessions crossing the reset hour are now split correctly between days.
- Daily medals are now awarded on **that day's** time, not all-time totals.
- Running timer survives the app being closed (stored as a start timestamp).
- Reset / import now update the screen immediately; invalid backup files are rejected safely.

## 🛠️ Tech

Flutter 3.41 · Dart 3 · `provider` · `shared_preferences` · `fl_chart` · `share_plus` · `file_picker` · `flutter_local_notifications`

```
lib/
  models/      data classes (Subject, Chapter, StudySession, settings…)
  logic/       day boundaries, stats, streaks, insights, achievements
  services/    storage, backup (v2 & v1 formats), alarm notifications
  state/       StudyStore (ChangeNotifier) – book, timer gate, auto-stop, pomodoro, CRUD
  screens/     Book, Today, Focus, Insights, Ranks, Profile, Alarm, Subject detail, Session log
  widgets/     rings, heatmap, calendar, forms
```

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the full analysis of v1 and the design of v2.

## ▶️ Run / build

```bash
cd version2
flutter pub get
flutter test            # 60 tests: day split, streaks, medals, v1 import, To-Do book & alarm edge cases
flutter run             # on a device / emulator
flutter build apk --release
```
