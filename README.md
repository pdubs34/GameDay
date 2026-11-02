# GameDay

An iOS app and home-screen widget for following your favorite teams. Pick your teams,
see their next game at a glance, and drop games into Apple Calendar.

Defaults to the Minnesota Wild.

## Features

- **Favorites** across the NHL, NFL, NBA, MLB, WNBA, and MLS, plus college football, men's basketball, and women's and men's volleyball. Every team shows its sport, so a school's football and volleyball teams are easy to tell apart
- **Next Game widget**: long-press it, choose **Edit Widget**, and pick up to 5 teams.
  - Home Screen (small, medium): tap the arrows to flip between your teams.
  - Lock Screen (rectangular, circular, inline): shows whichever of your teams plays next.
- **Add to Calendar**: add one game with the system sheet, or tap the calendar button on a team page to add
  the whole remaining schedule to a calendar named after the team. Running it again updates
  changed start times instead of creating duplicates.

Schedules come from ESPN's public site API (`site.api.espn.com`), which needs no API key.

## Building

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open GameDay.xcodeproj
```

To run on a real iPhone, choose your team under **Signing & Capabilities** for both targets.
If Xcode reports that the App Group is taken, change `group.com.pdubs34.gameday` in
`project.yml` and `Shared/FavoritesStore.swift` to an ID of your own.

## Layout

| Folder   | What's in it                                                    |
| -------- | --------------------------------------------------------------- |
| `Shared` | Models, ESPN client, favorites storage (used by both targets)   |
| `App`    | SwiftUI app: favorites list, team picker, schedule, calendar    |
| `Widget` | WidgetKit extension and its team-picker configuration intent    |
