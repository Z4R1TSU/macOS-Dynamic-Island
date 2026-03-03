---
name: island-best-practice
description: >
  Conventions, architecture, and design patterns for the boring.notch macOS Dynamic Island app.
  Use this skill whenever working on any feature, bugfix, or refactor in boring.notch — including
  adding new views, managers, settings, animations, or modifying the notch layout. Also consult
  this when the user asks about how the project works, how to add a new module, or when you need
  to understand the codebase structure before making changes.
---

# boring.notch Best Practices

boring.notch is a macOS app that replaces the MacBook's notch with a dynamic, interactive widget.
It displays music playback, notifications, system HUDs, calendar/weather, a file shelf, and more.

## Project Structure

```
boringNotch/
├── boringNotchApp.swift          # App entry, window creation, lifecycle
├── ContentView.swift             # Root view — notch shape, background, gestures, state routing
├── components/
│   ├── Notch/                    # Core notch UI (BoringHeader, NotchHomeView, NotchSettingsView, etc.)
│   ├── Calendar/                 # Calendar + weather widgets
│   ├── Shelf/                    # Drag & drop file shelf
│   ├── Settings/                 # External settings window
│   ├── Live activities/          # Download progress, HUD indicators
│   ├── Music/                    # Lyrics, visualizer, slider
│   ├── Tabs/                     # Tab bar (home/shelf/widgets)
│   ├── Webcam/                   # Camera preview
│   └── Onboarding/               # First-launch flow
├── managers/                     # Singleton ObservableObject managers
├── models/                       # BoringViewModel, Constants, data models
├── extensions/                   # SwiftUI View extensions, helpers
├── helpers/                      # Utility classes (AppleScript, AppIcons, etc.)
├── observers/                    # System event observers (media keys, fullscreen, drag)
├── sizing/                       # Notch dimensions and corner radii
├── enums/                        # App-wide enums
├── animations/                   # Animation definitions
├── private/                      # CGSSpace (auto-synced in Xcode)
├── metal/                        # Metal shaders (audio visualizer)
├── menu/                         # Status bar menu
└── utils/                        # Logging
```

## Architecture

### State Management — Three Layers

1. **`BoringViewModel`** — Per-screen notch state. Owns `notchState` (.open/.closed),
   `notchSize`, and transient UI state (hover, drop targeting, camera). Passed via
   `@EnvironmentObject` to all views.

2. **`BoringViewCoordinator`** — Global singleton (`BoringViewCoordinator.shared`). Controls
   which view is displayed (`currentView: NotchViews`), sneak peek / expanding view state,
   first-launch flow, and screen selection. Accessed via `@ObservedObject` in views.

3. **`Defaults` (sindresorhus/Defaults)** — Persisted user preferences. All keys live in
   `Constants.swift` under `extension Defaults.Keys`. Use `@Default(.keyName)` for reactive
   bindings in views, `Defaults[.keyName]` for read-only access.

### Adding a New Setting

1. Add the key to `Constants.swift`:
   ```swift
   static let myFeature = Key<Bool>("myFeature", default: false)
   ```
2. Use `@Default(.myFeature) var myFeature` in views that react to changes.
3. Add a toggle in `NotchSettingsView` (in-notch) and/or `SettingsView` (external window).

### Manager / Singleton Pattern

Every system-level service follows this pattern:

```swift
@MainActor
class FooManager: NSObject, ObservableObject {
    static let shared = FooManager()
    
    @Published var someState: Type = defaultValue
    
    private override init() {
        super.init()
        // setup observers, timers, etc.
    }
    
    func startMonitoring() { ... }
    func stopMonitoring() { ... }
}
```

Key rules:
- Always `@MainActor` if the manager drives UI via `@Published`.
- Use `static let shared` — never create multiple instances.
- Access in views with `@ObservedObject var foo = FooManager.shared`.
- Prefer `NSObject` base class when interfacing with system APIs (CoreAudio, CoreLocation, etc.).

### View Composition

ContentView is the root. It builds the notch layout in layers:

```
ContentView (body)
└── ZStack → VStack
    ├── NotchLayout()                    # Content inside the notch shape
    │   ├── [closed] state-specific views (music live activity, battery, HUD, notification, face)
    │   ├── [open] BoringHeader          # Top bar with tabs, notch cutout, action buttons
    │   ├── [closed] ClosedNotchWidgetBar  # Configurable widget indicators (market, pomodoro)
    │   └── [open] switch currentView:
    │       ├── .home       → NotchHomeView     # Music player + calendar/weather + pomodoro
    │       ├── .shelf      → ShelfView         # File shelf
    │       ├── .settings   → NotchSettingsView
    │       ├── .widgets    → WidgetHubView     # Widget management (market, calendar, pomodoro, music)
    │       ├── .market     → MarketTickerView  # Crypto/stock/gold prices
    │       └── .translation → TranslationView
    └── Chin rectangle (click target below notch)
```

The notch shape, background (solid black or liquid glass), clipping, and shadow are all
applied as modifiers on the `mainLayout` variable — not inside individual views.

When adding a new top-level view to the notch:
1. Add a case to `NotchViews` enum in `enums/generic.swift`.
2. Add the `case` to the `switch coordinator.currentView` in `ContentView.NotchLayout()`.
3. If the view needs a different notch size, update `vm.notchSize` when switching to it
   (see how `.settings` uses `settingsNotchSize`).

## Design Conventions

### Colors

| Context | Value |
|---------|-------|
| Notch background (solid) | `Color.black` |
| Notch background (glass) | `VisualEffectBlur(material: .popover, blendingMode: .behindWindow)` |
| Primary text | `.white` |
| Secondary text | `.gray` or `Color(white: 0.65)` |
| Dimmed text | `Color(white: 0.5)` |
| Accent | `Color.effectiveAccent` (respects system or custom accent) |
| Shadow | `.black.opacity(0.7)`, radius 4–6 |
| Subtle backgrounds | `Color.white.opacity(0.06)` (dark) or `.opacity(0.12)` (glass) |
| Buttons on glass | `Color.white.opacity(0.12)` capsule fill |

The app always uses `.preferredColorScheme(.dark)`. Never add light-mode styling.

### Typography

- Headers: `.system(.headline, design: .rounded)`
- Body: `.system(size: 12–14, weight: .medium)`
- Captions: `.system(size: 10–11)`
- Time/clock displays: `.system(size: ..., design: .rounded)` with `.monospacedDigit()`
- Section headers in settings: `.system(size: 10, weight: .semibold)`, uppercased

### Spacing & Sizing

| Constant | Value |
|----------|-------|
| `openNotchSize` | 660 × 200 |
| `settingsNotchSize` | 660 × 380 |
| Corner radii (open) | top: 19, bottom: 24 |
| Corner radii (closed) | top: 6, bottom: 14 |
| Album art corner radius | opened: 13, closed: 4 |
| Horizontal padding (open) | 12 |
| Content spacing | 0, 4, 6 (tight); 15 (between major sections) |

### Liquid Glass Mode

When `Defaults[.useLiquidGlass]` is true and the notch is **open**:
- Background: `Color.black` opacity animates to 0, then SwiftUI's native `.ultraThinMaterial`
  fades in. Use `Rectangle().fill(.ultraThinMaterial)` — never custom `VisualEffectBlur`.
  The black layer MUST become transparent (`opacity: 0`) for pure glass.
- The notch cutout fill in `BoringHeader` becomes `.clear`.
- Button capsules use `Color.white.opacity(0.12)` instead of `.black`.
- Section backgrounds use `Color.white.opacity(0.12)` instead of `0.06`.

When **closed**, the notch is always solid black regardless of the glass setting.

#### Glass-Mode Text & Icon Styling (Apple Design Guidelines)

On translucent glass backgrounds, text and icons need contrast assistance.
Use the shared modifiers in `VisualEffectBlur.swift`:

| Element | Modifier | Effect |
|---------|----------|--------|
| Primary text | `.glassText()` | White + drop shadow `(0.35, r:1, y:0.5)` |
| Secondary text | `.glassSecondaryText()` | White 75% + lighter shadow |
| Icons | `.glassIcon()` | White 90% + shadow |
| Card surface | `.glassSurface()` | `white.opacity(0.1)` fill + subtle top highlight |
| Adaptive | `.adaptiveText(isGlass:)` | Conditional glass/solid styling |

Key principles from Apple HIG for translucent surfaces:
- Always add a subtle drop shadow to text over glass — never rely on color alone.
- Use `foregroundStyle(.white)` not `.primary` on glass — system primary may be too dim.
- Icons should be slightly less opaque (0.9) than text for visual hierarchy.
- Card/section backgrounds on glass should be `white.opacity(0.08–0.12)`.
- Never use `Color.black` backgrounds on elements inside glass — use `Color.clear` or
  very low-opacity white instead.

## Animation Patterns

### Springs — Use These Specific Values

| Purpose | Animation |
|---------|-----------|
| Open/close notch, hover, gestures | `.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)` |
| Notch opening | `.spring(response: 0.42, dampingFraction: 0.8)` |
| Notch closing | `.spring(response: 0.45, dampingFraction: 1.0)` |
| View switching, settings | `.spring(response: 0.35, dampingFraction: 0.8)` |
| Drop animation | `.spring(.bouncy(duration: 0.4))` |
| Smooth transitions | `.smooth` or `.smooth(duration: 0.35)` |

### matchedGeometryEffect

Used for smooth transitions between closed and open states:
- `"albumArt"` — album art image morphs from small (closed) to large (open)
- `"spectrum"` — audio visualizer
- `"capsule"` — tab selection indicator

### Transitions

```swift
// Standard content transition
.transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))

// Notification appearance
.transition(.opacity.combined(with: .scale(scale: 0.95)))

// Settings slide-in
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .trailing).combined(with: .opacity)
))
```

### Gesture Handling

Gestures use `.panGesture(direction:)` (custom extension) with `gestureProgress` state.
The progress drives a `scaleEffect` on the entire notch. On completion, animate progress
back to zero with the interaction spring.

## Xcode Project Integration

Most files require **manual addition** to `project.pbxproj`. Only `private/` and
`BoringNotchXPCHelper/` use `fileSystemSynchronizedGroups`.

When creating a new Swift file:
1. Create the file in the correct directory.
2. Add a `PBXFileReference` entry (generate a unique ID like `AA00000100000007AABB0077`).
3. Add a `PBXBuildFile` entry pointing to the file reference.
4. Add the file reference to the parent `PBXGroup`'s `children` array.
5. Add the build file to the main target's `PBXSourcesBuildPhase` `files` array.

Key group IDs (for reference — grep the pbxproj to confirm):
- `managers`: `147163B52C5D804B0068B555`
- `Notch` (components): `B186542F2C6F455E000B926A`
- `extensions`: `B15063502C63D3F600EBB0E3`
- `Calendar` (components): contains `BoringCalendar.swift`

## Dependencies

| Package | Purpose |
|---------|---------|
| Defaults | Typed user preferences with SwiftUI bindings |
| KeyboardShortcuts | Global keyboard shortcut registration |
| LaunchAtLogin | Login item management |
| Sparkle | Auto-update framework |
| Lottie | Rich animations |
| SwiftUIIntrospect | Access underlying AppKit views |
| Pow | Additional animation effects |

## Enum Conventions

- Simple state enums: bare cases (`NotchState`, `NotchViews`, `Style`)
- User-facing enums with persistence: `String` raw values + `Defaults.Serializable`
- Add `CaseIterable, Identifiable` when used in pickers
- Associated values for complex state: `CalendarSelectionState`, `EventType`

## Common Patterns

### Conditional Modifiers
```swift
.conditionalModifier(someCondition) { view in
    view.someModifier()
}
```
Defined in `ConditionalModifier.swift`. Use instead of ternary-in-modifier for complex logic.

### Sneak Peek / Expanding View
Transient HUDs (volume, brightness, notifications) use `coordinator.toggleSneakPeek()`.
This shows a brief overlay in the closed notch, then auto-dismisses after a timeout.

### Window Management
The notch window is a borderless `NSPanel` (`BoringNotchSkyLightWindow`) with:
- `isOpaque = false`, `backgroundColor = .clear` (required for glass effect)
- `level = .screenSaver` (always on top)
- Positioned at the top-center of the screen, aligned with the hardware notch

### Hover-Out Behavior

All views close when the mouse leaves the notch — no "pinned" views. The `handleHover` handler
calls `self.vm.close()` whenever hover ends, and `close()` resets `currentView` to `.home`.

Guard `handleUpGesture` against expanded views (`.settings`, `.translation`, `.market`, `.widgets`)
to prevent scroll-triggered shrinking within those views.

### Widget System

Widgets (market, calendar, pomodoro, music) are managed via `WidgetHubView`, accessible from the
"Widgets" tab in `TabSelectionView`. Each widget has an enable toggle and a "show in closed notch"
option.

#### Home View Layout

The open notch home view (`NotchHomeView`) uses a two-row layout:
- **Top row**: Music player (full width, with optional camera).
- **Bottom row**: Horizontal widget row (`widgetRow`), driven by `Defaults[.homeWidgets]` — an
  ordered array of `HomeWidget` enum values (`.calendar`, `.market`, `.pomodoro`).
  Only enabled widgets are rendered. Each uses `.frame(maxWidth: .infinity)`. No scroll.

Key rules:
- Music is always on top — never moves, never reorderable.
- `openNotchSize` is 660×280 to accommodate both rows.
- New home widgets must be added to the `HomeWidget` enum.
- Each widget should be a compact, self-contained view with card backgrounds.

#### Closed Notch Widgets — Forbidden Zone Architecture

The hardware notch cutout is a **forbidden zone** — no widget content may be placed there.
All closed notch widget indicators follow the same compact pattern: `icon + data`, using
`.fixedSize()` and `.lineLimit(1)` to prevent overflow.

##### Layout: No Music Playing

`ClosedNotchWidgetBar` flanks the notch cutout (like `MusicLiveActivity`):
- If 1 widget: displayed on the **left** side, right-aligned toward the cutout.
- If 2 widgets: one on **left**, one on **right**, flanking the cutout.
- A black `Rectangle` fills the cutout gap (`closedNotchSize.width - cornerRadius`).
- Each side has 10pt inner padding from the cutout edge.

##### Layout: Music Playing

`ClosedNotchMusicWidgets` appends widget pills to the **right** of the music spectrum,
with 8pt leading padding. `computedChinWidth` adds 120px extra for these.

##### Sizing Safety

`computedChinWidth` is clamped to `windowSize.width - 20` to prevent overflow on small
screens. Each widget indicator uses `.fixedSize()` to render at natural width and prices
use `compactPrice` (e.g. `$67K` instead of `$67025`) when values are large.

Do NOT use separate "satellite pill" overlays — all widgets live within the notch shape.

#### Expanding View (Sneak Peek)

When transient notifications expand the closed notch (e.g. pomodoro completion, battery):
- Content is split as: left text | center notch gap | right text.
- The center gap matches `vm.closedNotchSize.width + 10`.
- Use `.frame(maxWidth: .infinity)` on both sides with `.trailing` / `.leading` alignment
  and inner padding (8pt) to prevent text from being hidden behind the notch cutout.
- The `computedChinWidth` must be set wide enough (e.g. 400 for pomodoro) in `ContentView`.

#### Music Sneak Peek

Music sneak peek / expanding view on song change is disabled. The `updateSneakPeek()` in
`MusicManager` is intentionally empty. Other sneak peek types (volume, brightness, battery,
pomodoro) remain active.

#### Music Waveform (Spectrum) Coloring — MANDATORY

The audio spectrum visualizer in the closed notch **MUST always** follow the album art's
dominant color. This is non-negotiable and must never be gated behind a user setting.

Rules:
- `MusicManager.calculateAverageColor()` must always be called inside `updateAlbumArt()` —
  never wrap it in a conditional (no `if Defaults[...]` guards).
- `MusicManager.avgColor` is the single source of truth for the album-derived color.
- The spectrum fill in `ClosedNotchContent.MusicLiveActivity` must always use
  `Color(nsColor: musicManager.avgColor).gradient` — never `.gray`, `.white`, or any
  hardcoded color.
- Song title and artist name text in the closed notch must also use
  `Color(nsColor: musicManager.avgColor)` — not `.gray`.
- The `coloredSpectrogram` setting key exists in `Constants.swift` but is **dead code** —
  it must NOT be checked anywhere in the rendering path. Do not re-introduce conditionals
  around spectrum coloring.
- If you modify `ClosedNotchContent`, `MusicLiveActivity`, or `MusicManager`, verify that
  `avgColor` is still unconditionally computed and used.

#### Music Waveform Animation — CANONICAL (Do Not Change)

The `AudioSpectrum` in `MusicVisualizer.swift` is the original animation from the project's
initial commit and MUST NOT be modified. It uses `Timer` + `CABasicAnimation` with
`autoreverses` for a bouncing effect:

**Exact parameters (do not alter):**
- `barCount = 4`, `barWidth = 2`, `spacing = barWidth` (2pt), `totalHeight = 14`
- Timer interval: `0.3` seconds
- Random target scale: `CGFloat.random(in: 0.35 ... 1.0)`
- `CABasicAnimation(keyPath: "transform.scale.y")`
  - `duration = 0.3`
  - `autoreverses = true`
  - `fillMode = .forwards`, `isRemovedOnCompletion = false`
  - `preferredFrameRateRange = (minimum: 24, maximum: 24, preferred: 24)`
- On pause: `removeAllAnimations()` + reset to `CATransform3DMakeScale(1, 0.35, 1)`
- `setPlaying(true)` starts the timer, `setPlaying(false)` stops + resets

**Forbidden changes:**
- Do NOT replace with sine waves, display links, CADisplayLink, or vDSP/FFT audio capture.
- Do NOT change the timer interval, scale range, duration, or autoreverses behavior.
- Do NOT add smooth interpolation or easing beyond what `autoreverses` provides.
- This is the intended design — simple, lightweight, and correct.

## Checklist for New Features

1. Create the manager (if needed) in `managers/` following the singleton pattern.
2. Add settings keys to `Constants.swift`.
3. Create views in the appropriate `components/` subdirectory.
4. Wire into `ContentView` — either in `NotchLayout()` for closed-state displays, or in
   the `switch coordinator.currentView` for open-state views.
5. Add `project.pbxproj` entries for all new files.
6. Add toggles to `NotchSettingsView` and/or `SettingsView`.
7. Use existing animation values — don't invent new spring constants.
8. Test both open and closed notch states, and with liquid glass on/off.
9. If the new view is full-height (like settings), add it to `scrollLocked` set in
   `handleUpGesture` and to the `needsTall` check in `onChange(of: currentView)`.
10. For widgets: add to `WidgetHubView` with enable toggle. Add a `HomeWidget` case
    for home view placement. Add to `homeWidgets` default order in `HomeWidget.defaultOrder`.
