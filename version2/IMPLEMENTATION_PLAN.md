# STP v2 — Analysis & Implementation Plan

## 1. Analysis of v1 (React Native / Expo)

v1 lives in the repository root and is **left untouched**. It is a 4-tab app:

| Tab | What it does |
|---|---|
| **Home** | Subjects → chapters, each chapter has its own stopwatch. Daily timer (day resets at 5 AM), global "level" goal (1000 / 5000 / 10000 h), subject filter, reorder, notes, categories, history modal. |
| **Rankings** | Subject / category leaderboards, gold/silver/bronze badges, "Hall of Fame" best days. |
| **Growth** | Line chart (1W / 1M / 1Y), goal progress ring, calendar heatmap, chapter leaderboard. |
| **Profile** | Name, avatar, trait tags, dark mode, JSON export / import, reset. |

### Problems found in v1

1. **History is deleted after 30 days** (`pruneOldLogs`) — so the 1Y chart and calendar can never show older data.
2. **Date keys don't match**: timers write local "5 AM day" keys, but the Growth chart reads `toISOString()` (UTC) keys → wrong/missing bars for Indian time (UTC+5:30).
3. **Sessions crossing the day boundary** are credited entirely to the day you press stop.
4. **Daily badges are awarded on all-time hours**, so the same subject wins gold every day.
5. Goal modal *Cancel* closes the wrong modal (`setModalVisible` instead of `setGoalModalVisible`).
6. *Reset all data* clears storage but not in-memory state (app still shows old data until restart).
7. Import does not restore the home filter or profile; a corrupt file can crash state.
8. Only aggregated totals are stored — no record of *when* you studied, so no time-of-day insights, no manual corrections.
9. 1M average divides 28 days of data by 30.

## 2. v2 goals

Rebuild in **Flutter (Material 3)** inside `version2/`, keep every v1 feature, fix the bugs above, and add new ideas.

### Core redesign: session-based data

Instead of only storing totals, v2 stores every **study session** (`subjectId`, `chapterId`, `start`, `end`). All totals, charts, streaks and rankings are *derived* from sessions. This fixes bugs 1–4 and 8 at the root and enables:

- Sessions split correctly across the 5 AM day boundary
- Manual "I forgot to start the timer" entries & deleting wrong sessions
- Hour-of-day productivity insights
- Unlimited history

The running timer is persisted as a start timestamp, so it survives the app being killed.

### New features (v2 ideas)

| Feature | Description |
|---|---|
| 🎯 **Focus Mode** | Full-screen distraction-free timer with a progress ring; stopwatch **or Pomodoro** (configurable work/break lengths, auto-cycles). |
| 🔥 **Streaks** | Current & longest streak based on a daily minimum. |
| 📅 **Daily goal ring** | Configurable minutes/day target on the dashboard. |
| 🟩 **Year heatmap** | GitHub-style 365-day contribution grid + monthly calendar. |
| 📊 **Richer analytics** | Bar charts (week / month / year), subject distribution donut, hour-of-day productivity chart, week-over-week comparison. |
| 🧠 **Smart insights** | "Your best hour is 9 PM", "+23 % vs last week", most-studied subject, average session length. |
| 🏅 **Achievements** | 15+ unlockable achievements (first session, 7-day streak, night owl, early bird, marathon 3 h session, 100 h club …). |
| ⭐ **XP & levels** | 1 XP per minute studied, levels with titles (Novice → Legend). |
| 🎨 **Personalisation** | Subject colours & emoji, 6 accent colours, light / dark / system theme. |
| ✅ **Syllabus tracking** | Chapters can be marked complete → subject syllabus %. |
| 📝 **Session log** | Browse/edit/delete every session, grouped by day. |
| 🔁 **v1 backup import** | Imports v1 `STP_Backup.json` files and converts them, so existing users keep their data. |

## 3. Architecture

```
lib/
  main.dart                 app entry, theme, providers
  models/                   Subject, Chapter, StudySession, Goal, Settings, Profile
  services/
    storage_service.dart    JSON persistence (shared_preferences)
    backup_service.dart     export / import (v2 + legacy v1 format)
  state/
    study_store.dart        ChangeNotifier: all data + timer + derived stats
  logic/
    day_utils.dart          5 AM day boundary, session splitting
    stats.dart              totals, streaks, heatmap, insights
    achievements.dart       achievement definitions & evaluation
  screens/                  home, focus, analytics, rankings, profile, subject detail, session log
  widgets/                  reusable cards, rings, heatmap, chips
```

- **State:** `provider` + `ChangeNotifier`
- **Storage:** `shared_preferences` (JSON)
- **Charts:** `fl_chart`
- **Backup:** `share_plus` (export) + `file_picker` (import)
- **Platform:** Android (APK), package `com.mayank.stp_v2` so it installs alongside v1.

## 4. Delivery

1. Branch `version-2` (separate from `main`, not merged).
2. Code in `version2/`; v1 files unchanged.
3. Unit tests for day-boundary splitting, streaks and v1 import.
4. Release APK built with `flutter build apk --release` and published as GitHub Release **v2.0.0** on the `version-2` branch.
