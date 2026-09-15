# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flupo is a managed developer platform and CLI tool for Flutter, inspired by the Expo/EAS ecosystem. Its goal is to eliminate native toolchain friction — removing the need for developers to maintain heavy local setups (Android Studio, Java/JDK, Xcode, Gradle) by using declarative native configuration (a `flupo.yaml` manifest) and cloud-based compilation runners.

**Current state:** this repo is at scaffold stage. Neither package has the product behavior described below implemented yet:
- `bin/flupo.dart` is the default `dart create` CLI template (just `--help`/`--verbose`/`--version` flags and echoing positional args).
- `flupo_go/` is the default `flutter create` counter-app template, unmodified.

Treat the "Core Architecture & Command Specifications" section below as the design target, not as existing behavior — verify against the actual code before assuming a command/feature exists.

## Repository Structure

This repo contains two independent, separately-versioned Dart/Flutter projects:

- **`/` (root)** — `flupo`, the pure-Dart CLI tool. Entrypoint: [bin/flupo.dart](bin/flupo.dart). Dependencies: `args`, `http`, `path`, `xml`, `yaml`.
- **`flupo_go/`** — `flupo_go`, the Flutter companion app ("Flupo Go") that will receive Hot Reload bytecode streamed from `flupo start`. Has its own `pubspec.yaml`, `analysis_options.yaml`, and platform folders (android/ios/linux/macos/windows/web).

Run Dart/Flutter commands from within the relevant project directory — `pub get`, `analyze`, and `test` are scoped per-package, not shared at the repo root.

## Commands

### Root CLI package (`flupo`)
```bash
dart pub get                    # install dependencies
dart run bin/flupo.dart <args>  # run the CLI (e.g. dart run bin/flupo.dart --help)
dart analyze                    # static analysis (package:lints/recommended.yaml)
dart format .                   # format code
dart test                       # run tests (no test/ directory exists yet)
```

### Flutter companion app (`flupo_go/`)
```bash
cd flupo_go
flutter pub get
flutter run                     # launch on a connected device/emulator
flutter analyze                 # static analysis (package:flutter_lints/flutter.yaml)
flutter test                    # run tests
flutter test test/widget_test.dart   # run a single test file
```

## Core Architecture & Command Specifications (design target)

### 1. `flupo init`
Scaffolds a baseline `flupo.yaml` file inside an existing Flutter project root. Detects project defaults from `pubspec.yaml` (name, version) and generates the initial config manifest.

### 2. `flupo patch`
Programmatically parses `flupo.yaml` and updates native boilerplate files without requiring manual XML/Plist edits.
- **Target files:** `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, build configurations.
- **Engine:** `package:xml` and `package:yaml` to inject permissions, bundle identifiers, and app metadata.

### 3. `flupo build`
Offloads binary compilation to remote cloud runners (e.g., GitHub Actions, Codemagic, or serverless build workers).
- Compresses project assets and codebase.
- Sends trigger payload via HTTP API to remote runner.
- Polls build status and streams terminal logs.
- Returns a terminal QR code, a direct APK/IPA download link, or triggers an ADB installation script over USB/Wi-Fi.

### 4. `flupo start`
Manages active local development and instant Hot Reload. Spins up a local Dart bundle server to stream updated Dart bytecode over local Wi-Fi/ADB directly to the **Flupo Dev Client** or the companion **Flupo Go** app (`flupo_go/`).

### 5. `flupo doctor`
Diagnostics tool. Checks for minimal environment prerequisites (Git, ADB, Dart SDK) without requiring heavy IDEs or Android SDKs.

## Configuration Manifest Spec (`flupo.yaml`)

```yaml
name: my_awesome_app
version: 1.0.0+1
identifier: com.example.myawesomeapp

permissions:
  camera: "Need camera access for profile photo"
  location: "Need location for delivery tracking"

build:
  target: apk
  runner: github_actions
```
