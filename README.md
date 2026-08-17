<div align="center">

# minrl

### Better Cmd+Tab for macOS

Minimized windows stay minimized when you Cmd+Tab. minrl fixes that.

![macOS 12.0+](https://img.shields.io/badge/macOS-12.0%2B-000000?style=flat-square&logo=apple&logoColor=white)

</div>

---

## Demo
![demo GIF for minrl](assets/demo.gif)


## The problem

Cmd+Tab is the fastest way to move between apps, but it has a blind spot. When
you minimize a window, switch away, and Cmd+Tab back, macOS quietly ignores
that window. The app becomes active, yet none of your windows appear. You are
left staring at the desktop, forced to reach for the Dock icon, and the
keyboard flow is broken.

Tools like DockDoor improve the switcher in other ways, but they do not solve
this specific gap. Minimized windows simply never come back with Cmd+Tab.

## What minrl does

minrl watches for Cmd+Tab. The moment your switch settles on an app, minrl
unminimizes every minimized window of that app, so the windows you expect are
there when you arrive.

Press Cmd+Tab. Your windows come back. Every time.

## Features

- Restores minimized windows on every app switch, no clicking required
- Runs as a menu bar app, so there is no Dock icon and no window of its own
- Supports Cmd+Tab, Cmd+Shift+Tab, and holding Tab to cycle through apps
- Press Esc to cancel a switch and nothing gets restored
- Native Objective-C with zero third-party dependencies
- Lightweight: one small binary that sits idle until you switch

## How it works

1. A global event tap listens for Cmd+Tab key presses.
2. When you release Cmd, minrl polls the frontmost app for a moment until the
   switcher settles on its target.
3. It then uses the macOS Accessibility API to unminimize every minimized
   window of that app.

The whole cycle feels instant, and the polling window means it works whether
you tap Cmd+Tab quickly or hold Tab to cycle through apps before releasing.

## Requirements

- macOS 12.0 or later
- Apple Silicon or Intel
- Accessibility permission, granted on first launch

## Install

### Build from source

minrl builds with clang and a plain Makefile.

```sh
git clone https://github.com/aaravmaloo/minrl.git
cd minrl
make bundle
open minrl.app
```

**Optionally: You can move the minrl.app bundle to your Applications folder.**

### GitHub Releases
You can also download the latest release from the [GitHub Releases](https://github.com/aaravmaloo/minrl/releases) page.

## Permissions

minrl needs Accessibility permission to do its job. It uses it for two things:
listening for Cmd+Tab and unminimizing windows.

On first launch, macOS prompts you automatically. You can also grant access
manually:

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Toggle **minrl** on

The menu bar item includes an **Open Accessibility Settings...** entry that
jumps straight there whenever you need it.


## Build targets

| Target             | Produces      | Notes                       |
| ------------------ | ------------- | --------------------------- |
| `make`             | `minrl`       | Debug build with symbols    |
| `make release`     | `minrl`       | Optimized binary            |
| `make bundle`      | `minrl.app`   | Release .app bundle         |
| `make debug-bundle`| `minrl.app`   | Debug .app bundle           |
| `make icon`        | `AppIcon.icns`| Regenerates the app icon    |
| `make clean`       | -             | Removes build artifacts     |

## Debugging

Set `MINRL_DEBUG=1` before launching to enable verbose logging:

```sh
MINRL_DEBUG=1 ./minrl
```

minrl always writes a log to `/tmp/minrl.log`, debug mode or not, so all
output lands there rather than the terminal. Debug mode fills that log with
extra detail, such as each detected switch and how many windows were
restored, and also saves a copy of the rendered status icon to
`/tmp/minrl_status_icon.png`, handy when tweaking the icon.

## Contributing
This project is small and focused on purpose. Bug reports and small, surgical
PRs are welcome. If you are planning something larger, open an issue first so
we can talk it through.
