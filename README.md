# Autoeng

English | [Korean](README.ko.md)

Start your terminal commands in English.

Autoeng is a macOS menu bar app that selects your preferred English input source when you switch to a terminal, move between terminal windows, or change iTerm2 tabs. If you manually choose another input source in the same window or tab, it stays selected.

## Features

- Works with iTerm2 and macOS Terminal.
- Switches to English on app entry and window changes, including separate processes of the same target app.
- Supports tab switching in iTerm2.
- Provides pause, resume, and manual switching from the **Auto / Eng** menu.
- Remembers your preferred English input source and target apps.

## Installation

Autoeng is currently installed from source. A Homebrew package is not available.

You need macOS, Apple Command Line Tools with Swift 6 or later, and Python 3 for the build scripts. The full Xcode app is not required.

### 1. Install Command Line Tools

If they are not already installed:

```sh
xcode-select --install
```

After installation, check the selected tools and Swift version:

```sh
xcode-select -p
xcrun swift --version
```

### 2. Build and launch

From the repository root:

```sh
# One-time local signing setup
./scripts/setup-local-signing.sh
./scripts/trust-local-signing.sh

./scripts/build-app.sh
open build/Autoeng.app
```

Local signing helps preserve Accessibility permission across rebuilds. The setup scripts create a signing identity on your Mac and configure user-level trust limited to the code-signing tool. An Apple Developer account is not required for this source build.

Generated certificates, private keys, and passwords stay in `.local-signing/`, which is excluded from Git. Keep this directory to preserve the app's identity. Quit Autoeng from its menu before rebuilding.

### 3. Enable window and tab detection

Open **System Settings → Privacy & Security → Accessibility**, add **`build/Autoeng.app`**, and enable it. Use `+` to add the app if it is not listed; Go to Folder (`⇧⌘G`) lets you select the project's `build` directory.

Relaunch the app after granting permission:

```sh
open build/Autoeng.app
```

Accessibility permission is required for window and tab detection. Switching when entering a target app works without it. If permission stops working after changing the signing identity, remove the old Accessibility entry and add the current app again.

## Usage

Open **Auto / Eng** in the menu bar:

1. Choose an installed English source, such as ABC or U.S., under **English input source**.
2. Enable iTerm2 or Terminal under **Target apps**.
3. Switch to a target app, another window, or another iTerm2 tab to start in English.

Use **Pause automatic switching** when you want to keep your input source across app, window, and tab changes. **Resume automatic switching** applies your English preference to the current target. **Switch to English** is also available while paused.

## Limitations

- iTerm2 tab detection requires a visible, accessible tab bar.
- Tab switching is supported in iTerm2, but not in the macOS Terminal app.
- Moving between split panes within the same tab does not trigger switching.
- Leaving a target app does not restore the previous input source.
- Older macOS versions, Intel Macs, and input methods other than Korean and English have not yet been verified.

## Privacy

Autoeng uses app activation and Accessibility selection state. It does not capture keystrokes, read terminal text or clipboard contents, or communicate over the network.

## License

[MIT](LICENSE).
