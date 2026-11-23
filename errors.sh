#!/bin/zsh
# Build and print only compiler errors (deduplicated).
cd "$(dirname "$0")"
./build.sh 2>&1 | grep -E "^/.*: error:" | sort -u | head -${1:-60}
./build.sh 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
