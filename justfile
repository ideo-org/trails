set shell := ["sh", "-c"]
set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]
set dotenv-load := true
set dotenv-filename := ".env"
set export

import? "local.justfile"

default_ios_device := env_var_or_default("IOS_DEVICE", "")
default_ios_configuration := env_var_or_default("IOS_CONFIGURATION", "Debug")
default_ios_derived_data := env_var_or_default("IOS_DERIVED_DATA", "build/ios/DerivedData")
default_ios_source_packages := env_var_or_default("IOS_SOURCE_PACKAGES_DIR", default_ios_derived_data + "/SourcePackages")
default_ios_reset_source_packages := env_var_or_default("IOS_RESET_SOURCE_PACKAGES", "false")
default_ios_test_derived_data := env_var_or_default("IOS_TEST_DERIVED_DATA", "build/ios/TestDerivedData")
default_ios_test_source_packages := env_var_or_default("IOS_TEST_SOURCE_PACKAGES_DIR", default_ios_test_derived_data + "/SourcePackages")
default_ios_test_results := env_var_or_default("IOS_TEST_RESULTS_DIR", "build/ios/TestResults")

# Usage:
#   just ios
#   just ios device="00008122-001C4899226A001C"
#   just ios device="Hiro's iPhone" configuration=Release
#
# Defaults can also come from `.env`:
#   IOS_DEVICE=00008101-001224822130001E
#   IOS_CONFIGURATION=Debug
#   IOS_DERIVED_DATA=build/ios/DerivedData
#   IOS_SOURCE_PACKAGES_DIR=build/ios/DerivedData/SourcePackages
#   IOS_RESET_SOURCE_PACKAGES=false

# Build, install, launch, and attach to the app console until it exits.
ios device=default_ios_device configuration=default_ios_configuration derived_data=default_ios_derived_data source_packages=default_ios_source_packages:
    IOS_DEVICE="{{device}}" IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" IOS_RESET_SOURCE_PACKAGES="{{default_ios_reset_source_packages}}" bun run ./scripts/ios-device.ts

# Non-waiting install handoff for agents and skills.
ios-agent device=default_ios_device configuration=default_ios_configuration derived_data=default_ios_derived_data source_packages=default_ios_source_packages:
    IOS_DEVICE="{{device}}" IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" IOS_RESET_SOURCE_PACKAGES="{{default_ios_reset_source_packages}}" bun run ./scripts/ios-device.ts --no-wait

# Build the iOS app without installing or launching it.
# Uses the same `.env` defaults and CLI overrides as `just ios`.
ios-build device=default_ios_device configuration=default_ios_configuration derived_data=default_ios_derived_data source_packages=default_ios_source_packages:
    IOS_DEVICE="{{device}}" IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" IOS_RESET_SOURCE_PACKAGES="{{default_ios_reset_source_packages}}" bun run ./scripts/ios-device.ts --build-only

# Build and run the iOS UI test suite on a connected physical device.
# Usage:
#   just ios-test
#   just ios-test device="00008101-001224822130001E"
ios-test device=default_ios_device configuration=default_ios_configuration derived_data=default_ios_test_derived_data source_packages=default_ios_test_source_packages results=default_ios_test_results:
    IOS_DEVICE="{{device}}" IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" IOS_TEST_RESULTS_DIR="{{results}}" IOS_RESET_SOURCE_PACKAGES="{{default_ios_reset_source_packages}}" bun run ./scripts/ios-device.ts --test

# List connected physical iOS devices that `just ios` can target.
ios-devices:
    bun run ./scripts/ios-device.ts --list

# List available iOS simulators.
ios-simulators:
    bun run ./scripts/ios-device.ts --list-simulators

# Build, install, and launch the iOS app on the booted simulator (or boot one if none are).
# Usage:
#   just ios-simulator
#   just ios-simulator simulator="iPhone 15 Pro"
ios-simulator simulator='iPhone SE' configuration=default_ios_configuration derived_data=default_ios_derived_data source_packages=default_ios_source_packages:
    IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" bun run ./scripts/ios-device.ts --simulator "{{simulator}}"

# Build and run the iOS UI test suite on a simulator.
ios-simulator-test simulator='iPhone SE' configuration=default_ios_configuration derived_data=default_ios_test_derived_data source_packages=default_ios_test_source_packages results=default_ios_test_results:
    IOS_CONFIGURATION="{{configuration}}" IOS_DERIVED_DATA="{{derived_data}}" IOS_SOURCE_PACKAGES_DIR="{{source_packages}}" IOS_TEST_RESULTS_DIR="{{results}}" bun run ./scripts/ios-device.ts --test --simulator "{{simulator}}"

# Preserve the existing open-in-Xcode workflow.
ios-open:
    open ios/Trails.xcodeproj

# Run the local shipping script to build and upload to TestFlight.
ship:
    ./ship.command

# Alias for pushing to TestFlight.
testflight: ship

# Kill process using port 8095
kill-dev:
    bunx kill-port 8095

# Clean up port 8095 and run the backend dev server (port 8095) with tsx
dev *ARGS:
    bunx kill-port 8095
    cd trails.logos; just dev {{ARGS}}

# Alias for dev
restart-dev *ARGS:
    just dev {{ARGS}}

# Run trails.logos tests
test-backend:
    cd trails.logos; just test

# Run trails.logos acceptance demonstration
demo-backend:
    cd trails.logos; just demo
