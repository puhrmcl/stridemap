# Under

**The daily check-in for staying under.**

Under is a five-second evening pause: *was today a quiet day?* It is not a budget
app, not an expense tracker, not a shared wallet, and not a no-buy challenge. It
never asks what you bought or how much it cost.

- **Four buckets, no amounts** — none, low (≤ $25), mid ($25–$100), high (> $100).
  Exactly $25 is low; exactly $100 is mid. The UI calls them quiet / low / mid / high.
- **One person or two** — each person has a first name and their own log. A
  check-in is always one person's answer. There is no household total, no shared
  wallet, and nobody answers for anybody else.
- **1–3 taps, no keyboard** — "Spend today?" → "Under $25?" → "Under $100?".
- **Your streak only** — consecutive quiet days for you. Never you-vs-them.
- **A high day is a colour, then silence** — no scolding copy, no push about
  what the other person logged.

## Running it

Open `Under.xcodeproj` in Xcode 26 (or later) and run the **Under** scheme on any
iOS 18+ simulator. Nothing else is needed: no Apple Developer account, no signing
team, no iCloud, no backend. The project ships no `DEVELOPMENT_TEAM`, so a
simulator build works on a clean machine; add your team in *Signing & Capabilities*
when you want it on a device.

Try both shapes from onboarding:

- **Solo** — one log, no person row on home.
- **Two people** — two names, two independent marks per day on the calendar, and
  a tap on a name to switch who is checking in.

To see the calendar populated immediately, use the SwiftUI previews
(`HomeView`, `MonthCalendarView`), which are seeded from `UnderStore.preview`.

## Layout

```
Under/
├─ UnderApp.swift          App entry, store + notification delegate wiring
├─ Model/
│  ├─ Bucket.swift         none / low / mid / high, and what "quiet" means
│  ├─ Person.swift         A first name and an identity
│  ├─ DayLog.swift         One person's answer for one local day
│  ├─ DayKey.swift         Local-calendar day keys ("yyyy-MM-dd") and week helpers
│  └─ SpendRule.swift      The rulebook copy, in one place
├─ Store/
│  ├─ AppState.swift       Everything persisted (tolerant Codable)
│  ├─ Persistence.swift    UserDefaults storage + an in-memory one for previews
│  ├─ UnderStore.swift     Source of truth: people, logs, streaks, rollover
│  ├─ Reminder.swift       The evening local notification + its quick actions
│  └─ PreviewData.swift    Seeded stores for previews (DEBUG only)
├─ Design/
│  ├─ Theme.swift          Light/dark palette; the four mark colours
│  └─ Components.swift     Wordmark, answer button, day mark, person pill
└─ Views/
   ├─ RootView.swift       Onboarding or home; day rollover on foreground
   ├─ OnboardingView.swift Three screens: the line, the rule, who's using it
   ├─ HomeView.swift       Check-in when unlogged; streak + calendar when logged
   ├─ CheckInView.swift    The 1–3 tap flow
   ├─ MonthCalendarView.swift  One mark per person per day, never averaged
   ├─ DayDetailView.swift  Tap a day; only today is editable, only your bucket
   ├─ RecapView.swift      "5 quiet days." — opened, never pushed
   ├─ SettingsView.swift   Names, solo/two, rule, reminder, quiet day
   └─ SpendRuleView.swift  The rule, read-only
```

## Decisions

- **Storage is a small JSON blob in `UserDefaults`, not SwiftData.** The whole
  model is people plus one bucket per person per day — a few kilobytes. A store
  this small does not earn a persistent container, and it keeps the app running
  anywhere with no setup. `StateStorage` is a protocol, so swapping in SwiftData
  or a file later touches one type.
- **Days are keyed by the local calendar date.** That is what makes "you can
  change today's log until midnight, then it locks" mean *your* midnight. The key
  is built from `Calendar` components, so no locale or time-zone drift creeps in,
  and the app re-reads the day whenever it comes to the foreground.
- **CloudKit pairing was skipped.** It needs a paid developer account, an iCloud
  container and entitlements — which would break "runs in the Simulator with no
  account". v1 is one device; two people switch with a tap on the name. The
  invite-code flow can land later without touching the model: `DayLog` is already
  per-person and independently mergeable.
- **Notification quick actions are solo-only.** Letting a notification log
  straight from the lock screen is good; letting it log for whoever happens to be
  the active person in a two-person household is not.
- **The streak tolerates an unlogged today.** An evening that has not happened
  yet is not a broken streak, so the count is measured from yesterday until you
  check in.

## What is deliberately absent

Budgets, transactions, receipts, categories, notes, exact amounts, search,
export, split bills, who-paid, accounts, a paywall, comments on a day, badges,
charts of money, an "us" streak on home, an averaged household colour, and any
way to hide a log from the other person.
