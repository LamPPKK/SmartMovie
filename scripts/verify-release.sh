#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
train_file="$repo_root/release/train.json"
contract_file="$repo_root/backend/worker/contract/v2/openapi.json"
contract_manifest="$repo_root/backend/worker/contract/v2/manifest.json"
legacy_contract_file="$repo_root/backend/worker/contract/openapi.json"
legacy_contract_manifest="$repo_root/backend/worker/contract/manifest.json"

read_json() {
  node -e 'const fs=require("node:fs"); const value=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); console.log(process.argv[2].split(".").reduce((current, key) => current[key], value));' "$1" "$2"
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{ print $1 }'
  else
    sha256sum | awk '{ print $1 }'
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

fixtures_sha256() {
  local directory="$1"
  (
    cd "$directory"
    while IFS= read -r -d '' fixture; do
      printf '%s  %s\n' "$(sha256_file "$fixture")" "$fixture"
    done < <(find . -type f -name '*.json' -print0 | sort -z)
  ) | sha256_stream
}

expected_version="$(read_json "$train_file" train_version)"
expected_build="$(read_json "$train_file" apple.build_number)"
manifest_marketing_version="$(read_json "$train_file" apple.marketing_version)"
expected_contract_version="$(read_json "$train_file" contract_version)"
expected_checksum="$(read_json "$train_file" contract_openapi_sha256)"

project_version="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$repo_root/SmartMovie/project.yml")"
project_build="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$repo_root/SmartMovie/project.yml")"
worker_version="$(read_json "$repo_root/backend/worker/package.json" version)"
openapi_version="$(read_json "$contract_file" info.version)"
manifest_contract_version="$(read_json "$contract_manifest" contract_version)"
manifest_checksum="$(read_json "$contract_manifest" openapi_sha256)"
expected_fixtures_checksum="$(read_json "$contract_manifest" fixtures_sha256)"
actual_checksum="$(sha256_file "$contract_file")"
actual_fixtures_checksum="$(fixtures_sha256 "$repo_root/backend/worker/contract/v2/fixtures")"
legacy_version="$(read_json "$legacy_contract_file" info.version)"
legacy_manifest_version="$(read_json "$legacy_contract_manifest" contract_version)"

[[ "$project_version" == "$expected_version" ]] || { printf 'Apple MARKETING_VERSION %s does not match train %s\n' "$project_version" "$expected_version"; exit 1; }
[[ "$manifest_marketing_version" == "$expected_version" ]] || { printf 'Apple manifest version %s does not match train %s\n' "$manifest_marketing_version" "$expected_version"; exit 1; }
[[ "$worker_version" == "$expected_version" ]] || { printf 'Worker version %s does not match train %s\n' "$worker_version" "$expected_version"; exit 1; }
[[ "$project_build" == "$expected_build" ]] || { printf 'Apple build %s does not match release manifest %s\n' "$project_build" "$expected_build"; exit 1; }
[[ "$openapi_version" == "$expected_contract_version" ]] || { printf 'OpenAPI version %s does not match train contract %s\n' "$openapi_version" "$expected_contract_version"; exit 1; }
[[ "$manifest_contract_version" == "$expected_contract_version" ]] || { printf 'Contract manifest version %s does not match train contract %s\n' "$manifest_contract_version" "$expected_contract_version"; exit 1; }
[[ "$actual_checksum" == "$expected_checksum" ]] || { printf 'OpenAPI checksum %s does not match train %s\n' "$actual_checksum" "$expected_checksum"; exit 1; }
[[ "$manifest_checksum" == "$expected_checksum" ]] || { printf 'Contract manifest checksum %s does not match train %s\n' "$manifest_checksum" "$expected_checksum"; exit 1; }
[[ "$actual_fixtures_checksum" == "$expected_fixtures_checksum" ]] || { printf 'Fixture checksum %s does not match contract manifest %s\n' "$actual_fixtures_checksum" "$expected_fixtures_checksum"; exit 1; }
[[ "$legacy_version" == "1.0.0" && "$legacy_manifest_version" == "1.0.0" ]] || { printf '/v1 contract must remain frozen at 1.0.0 while SmartMovie 2.0 is supported.\n'; exit 1; }

printf 'Release train %s and catalog contract %s are consistent.\n' "$expected_version" "$expected_contract_version"
