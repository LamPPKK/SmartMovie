#!/usr/bin/env bash

set -euo pipefail

repo_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
contract_commit="$(git -C "$repo_dir" log -1 --format=%H -- backend/worker/contract release/train.json)"

if [[ ! "$contract_commit" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Unable to resolve the canonical contract commit.\n' >&2
  exit 1
fi

printf '%s\n' "$contract_commit"
