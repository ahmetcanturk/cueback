#!/bin/sh
# Builds cueback from source and installs it on this Mac (see setup.sh for what that adds).
# To give cueback to someone else without building, use package.sh.
set -e
cd "$(dirname "$0")/.."
swift build -c release
stage=.build/stage
rm -rf "$stage" && mkdir -p "$stage"
cp "$(swift build -c release --show-bin-path)/cueback" skill/SKILL.md "$stage/"
sh scripts/setup.sh "$stage"
