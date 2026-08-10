# Changelog

All notable changes to Etch are recorded here. Build/delivery is automated:
pushes to `claude/rebrand-etch` trigger an Xcode Cloud build that delivers to
TestFlight (Internal Testing).

## [Unreleased]

### Added
- Multi-source activity import with Apple Health (HealthKit) as the primary
  provider — any app that writes runs to Health (Apple Workouts, Nike, Garmin,
  COROS, Polar, Wahoo, adidas, Runna, Strava) shows up on the map.
- Strava as an optional *enrichment* provider (titles, gear, races, locations).
- `ActivityProvider` protocol abstraction so new ecosystems can be added without
  touching the import service or UI.
- Cloudflare Worker token proxy so the Strava client secret never ships in the app.
- macOS GitHub Actions CI build check on every push/PR.
- Landing + support + privacy pages hosted on GitHub Pages.

### Changed
- Rebranded StrideMap → **Etch** (bundle id `com.nwagtech.etch`).
- Accent tuned to ember (`#FF5B2B`) to match the app icon.

### Fixed
- Duplicate `Info.plist` build error in the synchronized project group.
- Main-actor isolation error in the provider layer (Xcode 26 strict concurrency).
