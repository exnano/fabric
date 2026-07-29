#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
    print "XcodeGen is required. Install it with: brew install xcodegen" >&2
    exit 69
fi

cd "$ROOT_DIR"
xcodegen generate
print "Generated $ROOT_DIR/ExnanoFabric.xcodeproj"
