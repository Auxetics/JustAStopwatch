<p align="center">
  <img src="stopwatch_transparent.png" width="128" alt="JustAStopwatch Logo">
</p>

# JustAStopwatch

A perfectly lightweight, cross-platform, bloat-free stopwatch application for your macOS menu bar and Windows taskbar. Designed with performance and simplicity in mind, it provides the precise functionality you need without the unnecessary telemetry or tracking of other alternatives.

## Features

- **Cross-Platform Parity**: Available natively for both macOS (Menu Bar) and Windows (Taskbar overlay) with an identical feature set.
- **Click to Start/Pause**: A single left click on the timer instantly starts or pauses it.
- **Double-Click to Reset**: Rapidly double-click the timer to reset it back to zero.
- **Dynamic Formatting**: Keeps your taskbar and menu bar tidy. Displays as `MM:SS` (e.g. `00:00`), automatically expanding to `HH:MM:SS` when your timer reaches an hour.
- **Right-Click Menu**: Access application settings cleanly without interrupting your timer.
- **Launch on Startup**: Configure the app to automatically launch in the background when you log into your Mac or PC.
- **Over-The-Air Updates**: Built-in silent auto-updater securely checks GitHub Releases for new versions and smoothly applies them with a single click. (Protected by a safety guardrail that prevents updating while the timer is running!)

## Installation

### macOS
1. Navigate to the [Releases](https://github.com/Auxetics/JustAStopwatch/releases) tab.
2. Download the latest `JustAStopwatch.dmg` file.
3. Open the downloaded `.dmg` and drag the application directly into your `/Applications` folder.

### Windows
1. Navigate to the [Releases](https://github.com/Auxetics/JustAStopwatch/releases) tab.
2. Download the latest `JustAStopwatch.exe` file.
3. Simply run the file! The standalone executable will securely self-install into your `%AppData%` folder on first launch so you don't have to worry about accidentally deleting it.

## Troubleshooting

### macOS Security
Due to strict Apple security rules on some macOS versions (like macOS Sequoia or later), you might see a warning when opening the app for the first time. Simply right-click the app in your Applications folder and select **Open** to bypass this one-time warning.
