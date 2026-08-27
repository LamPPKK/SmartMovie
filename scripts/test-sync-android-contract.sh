#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

source_dir="$fixture_root/source"
mkdir -p \
  "$source_dir/backend/worker/contract" \
  "$source_dir/release"
git -C "$source_dir" init --quiet
printf '{"contract_version":"2.0.0"}\n' > "$source_dir/backend/worker/contract/manifest.json"
printf '{"version":"3.0.0"}\n' > "$source_dir/release/train.json"
git -C "$source_dir" add backend/worker/contract release/train.json
git -C "$source_dir" \
  -c user.name=smartmovie-contract-test \
  -c user.email=actions@users.noreply.github.com \
  commit --quiet -m 'seed canonical contract'
canonical_commit="$(git -C "$source_dir" rev-parse HEAD)"

mkdir -p "$source_dir/.github/workflows"
printf 'name: Contract sync\n' > "$source_dir/.github/workflows/contract-sync.yml"
git -C "$source_dir" add .github/workflows/contract-sync.yml
git -C "$source_dir" \
  -c user.name=smartmovie-contract-test \
  -c user.email=actions@users.noreply.github.com \
  commit --quiet -m 'change only contract workflow'
workflow_commit="$(git -C "$source_dir" rev-parse HEAD)"
resolved_commit="$("$repo_root/scripts/resolve-contract-source-commit.sh" "$source_dir")"
if [[ "$resolved_commit" != "$canonical_commit" || "$resolved_commit" == "$workflow_commit" ]]; then
  printf 'Workflow-only changes must not replace canonical contract provenance.\n' >&2
  exit 1
fi

android_dir="$fixture_root/android"
mkdir -p "$android_dir"
git -C "$android_dir" init --quiet

first_commit="$resolved_commit"
second_commit="2222222222222222222222222222222222222222"

"$repo_root/scripts/sync-android-contract.sh" "$android_dir" "$first_commit"
python3 - "$android_dir/catalog-contract/manifest.json" "$first_commit" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)

assert manifest["upstream_commit"] == sys.argv[2]
assert manifest["legacy_v1_contract_version"] == "1.0.0"
assert set(manifest) == {
    "schema_version",
    "contract_version",
    "upstream_repository",
    "upstream_commit",
    "openapi_sha256",
    "fixtures_sha256",
    "legacy_v1_contract_version",
}
PY

git -C "$android_dir" add catalog-contract release/train.json
git -C "$android_dir" \
  -c user.name=smartmovie-contract-test \
  -c user.email=actions@users.noreply.github.com \
  commit --quiet -m 'seed contract snapshot'

"$repo_root/scripts/sync-android-contract.sh" "$android_dir" "$first_commit"
if [[ -n "$(git -C "$android_dir" status --porcelain -- catalog-contract release/train.json)" ]]; then
  printf 'Repeated synchronization must be a no-op.\n' >&2
  exit 1
fi

"$repo_root/scripts/sync-android-contract.sh" "$android_dir" "$second_commit"
changed_paths="$(git -C "$android_dir" status --porcelain -- catalog-contract release/train.json)"
if [[ "$changed_paths" != ' M catalog-contract/manifest.json' ]]; then
  printf 'Changing only the upstream commit must update only catalog-contract/manifest.json; got: %s\n' "$changed_paths" >&2
  exit 1
fi

"$repo_root/scripts/sync-android-contract.sh" "$android_dir" "$second_commit"
if [[ "$(git -C "$android_dir" status --porcelain -- catalog-contract release/train.json)" != "$changed_paths" ]]; then
  printf 'Repeated synchronization with a new commit must remain deterministic.\n' >&2
  exit 1
fi

printf 'Android contract synchronization is complete and idempotent.\n'
