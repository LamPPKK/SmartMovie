#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <android-repository-directory> <upstream-commit>\n' "$0" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$1"
upstream_commit="$2"
contract_root="$repo_root/backend/worker/contract"

if [[ ! "$upstream_commit" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Upstream commit must be a full lowercase SHA-1.\n' >&2
  exit 64
fi

if [[ ! -d "$android_dir/.git" ]]; then
  printf 'Android repository is not a Git checkout: %s\n' "$android_dir" >&2
  exit 66
fi

mkdir -p \
  "$android_dir/catalog-contract/v1" \
  "$android_dir/catalog-contract/v2" \
  "$android_dir/release"
rsync -a --delete --exclude 'v2/' \
  "$contract_root/" \
  "$android_dir/catalog-contract/v1/"
rsync -a --delete \
  "$contract_root/v2/" \
  "$android_dir/catalog-contract/v2/"
cp "$repo_root/release/train.json" "$android_dir/release/train.json"

python3 - \
  "$android_dir/catalog-contract/manifest.json" \
  "$contract_root/v2/manifest.json" \
  "$contract_root/manifest.json" \
  "$upstream_commit" <<'PY'
import json
import sys

destination, canonical_v2_path, canonical_v1_path, commit = sys.argv[1:]
with open(canonical_v2_path, encoding="utf-8") as source:
    canonical_v2 = json.load(source)
with open(canonical_v1_path, encoding="utf-8") as source:
    canonical_v1 = json.load(source)

snapshot = {
    "schema_version": 1,
    "contract_version": canonical_v2["contract_version"],
    "upstream_repository": "LamPPKK/Smart-Movie-iOS",
    "upstream_commit": commit,
    "openapi_sha256": canonical_v2["openapi_sha256"],
    "fixtures_sha256": canonical_v2["fixtures_sha256"],
    "legacy_v1_contract_version": canonical_v1["contract_version"],
}
with open(destination, "w", encoding="utf-8") as output:
    json.dump(snapshot, output, indent=2)
    output.write("\n")
PY
