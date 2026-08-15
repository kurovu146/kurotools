#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# `make rust` rebuilds the Rust core and wipes .build if the staticlib actually
# changed — SwiftPM doesn't track it as a build input, so a bare `swift build`
# here would silently keep linking a stale Rust binary into the release build.
make rust
swift build -c release
echo "Built: .build/release/KuroTools and .build/release/kurovitals-helper"
