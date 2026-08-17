#!/usr/bin/env bash

set -u

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is available"
  else
    fail "$1 is required"
  fi
}

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_dir" == */Xcode.app/Contents/Developer ]]; then
  pass "full Xcode toolchain is selected ($developer_dir)"
else
  fail "select the full Xcode toolchain; current developer directory is '${developer_dir:-unavailable}'"
fi

require_command xcodebuild
require_command swift
require_command xcodegen
require_command swiftlint
require_command node
require_command npm

swift_version="$(swift --version 2>/dev/null | head -n 1 || true)"
if [[ "$swift_version" =~ Swift[[:space:]]version[[:space:]]6\. ]]; then
  pass "$swift_version"
else
  fail "Swift 6 is required; detected '${swift_version:-unavailable}'"
fi

node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
if [[ "$node_major" == "24" ]]; then
  pass "Node.js $(node --version)"
else
  fail "Node.js 24 is required; detected '${node_major:-unavailable}'"
fi

if (( failures > 0 )); then
  printf '\nDoctor found %d blocking issue(s). No system changes were made.\n' "$failures"
  exit 1
fi

printf '\nSmartMovie Apple/Worker development environment is ready.\n'
