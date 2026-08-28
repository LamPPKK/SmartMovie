#!/usr/bin/env bash

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
github_repository="${SMARTMOVIE_GITHUB_REPOSITORY:-LamPPKK/Smart-Movie-iOS}"
failures=0
warnings=0
preflight_temp_dir=""

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

warn() {
  printf 'WARN  %s\n' "$1"
  warnings=$((warnings + 1))
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is available"
    return 0
  fi
  fail "$1 is required"
  return 1
}

contains_line() {
  printf '%s\n' "$1" | grep -Fqx "$2"
}

check_source_release() {
  local output
  if output="$("$repo_root/scripts/verify-release.sh" 2>&1)"; then
    pass "source release train and contract checksums are consistent"
  else
    fail "source release verification failed: $(printf '%s\n' "$output" | tail -n 1)"
  fi
}

check_environment_secrets() {
  local environment="$1"
  local names
  local required
  if ! names="$(gh secret list --repo "$github_repository" --env "$environment" --json name --jq '.[].name' 2>/dev/null)"; then
    fail "GitHub environment '$environment' is missing or its secrets are not readable"
    return
  fi

  required="CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN AUTH_D1_DATABASE_ID TMDB_BEARER_TOKEN SESSION_ENCRYPTION_KEY"
  if [[ "$environment" == "staging" ]]; then
    required="$required SMARTMOVIE_ACCOUNT_SESSION_TOKEN"
  fi
  for name in $required; do
    if contains_line "$names" "$name"; then
      pass "GitHub $environment secret $name is configured"
    else
      fail "GitHub $environment secret $name is missing"
    fi
  done
}

check_repository_secrets() {
  local names
  if ! names="$(gh secret list --repo "$github_repository" --json name --jq '.[].name' 2>/dev/null)"; then
    fail "repository secrets for $github_repository are not readable"
    return
  fi
  if contains_line "$names" "ANDROID_CONTRACT_SYNC_TOKEN"; then
    pass "repository secret ANDROID_CONTRACT_SYNC_TOKEN is configured"
  else
    fail "repository secret ANDROID_CONTRACT_SYNC_TOKEN is missing"
  fi
}

check_production_environment_protection() {
  local details
  local validation_error
  if ! details="$(gh api "repos/$github_repository/environments/production" 2>/dev/null)"; then
    fail "GitHub production environment protection is not readable"
    return
  fi
  if validation_error="$(printf '%s' "$details" | python3 -c '
import json
import sys

value = json.load(sys.stdin)
rules = value.get("protection_rules") or []
reviewers = [
    reviewer
    for rule in rules
    if rule.get("type") == "required_reviewers"
    for reviewer in (rule.get("reviewers") or [])
]
policy = value.get("deployment_branch_policy") or {}
problems = []
if not reviewers:
    problems.append("at least one required reviewer is missing")
if not (policy.get("protected_branches") is True or policy.get("custom_branch_policies") is True):
    problems.append("deployment branches are unrestricted")
if problems:
    print("; ".join(problems))
    raise SystemExit(1)
')"; then
    pass "GitHub production environment requires approval and restricts deployment branches"
  else
    fail "GitHub production environment is not protected: $validation_error"
  fi
}

check_android_main_contract() {
  local manifest_file="$preflight_temp_dir/android-contract-manifest.json"
  local release_file="$preflight_temp_dir/android-release-train.json"
  local manifest_status
  local release_status
  local validation_error
  local canonical_commit

  if ! canonical_commit="$("$repo_root/scripts/resolve-contract-source-commit.sh" "$repo_root" 2>/dev/null)"; then
    fail "canonical contract source commit could not be resolved"
    return
  fi

  if ! manifest_status="$(curl --silent --show-error --max-time 20 --output "$manifest_file" --write-out '%{http_code}' \
      "https://raw.githubusercontent.com/LamPPKK/Smart-Movie-Android/main/catalog-contract/manifest.json")"; then
    fail "Android main contract manifest could not be downloaded"
    return
  fi
  if ! release_status="$(curl --silent --show-error --max-time 20 --output "$release_file" --write-out '%{http_code}' \
      "https://raw.githubusercontent.com/LamPPKK/Smart-Movie-Android/main/release/train.json")"; then
    fail "Android main release manifest could not be downloaded"
    return
  fi
  if [[ "$manifest_status" != "200" || "$release_status" != "200" ]]; then
    fail "Android main release inputs returned HTTP contract=$manifest_status release=$release_status"
    return
  fi

  if validation_error="$(python3 - \
      "$repo_root/backend/worker/contract/v2/manifest.json" \
      "$repo_root/release/train.json" \
      "$manifest_file" \
      "$release_file" \
      "$canonical_commit" <<'PY'
import json
import sys

local_contract_path, local_release_path, remote_contract_path, remote_release_path, canonical_commit = sys.argv[1:]
with open(local_contract_path, encoding="utf-8") as handle:
    local_contract = json.load(handle)
with open(local_release_path, encoding="utf-8") as handle:
    local_release = json.load(handle)
with open(remote_contract_path, encoding="utf-8") as handle:
    remote_contract = json.load(handle)
with open(remote_release_path, encoding="utf-8") as handle:
    remote_release = json.load(handle)

problems = []
for key in ("contract_version", "openapi_sha256", "fixtures_sha256"):
    if remote_contract.get(key) != local_contract.get(key):
        problems.append(f"{key} differs")
for key in ("train_version", "contract_version", "contract_openapi_sha256"):
    if remote_release.get(key) != local_release.get(key):
        problems.append(f"release {key} differs")
if remote_contract.get("upstream_commit") != canonical_commit:
    problems.append("canonical upstream_commit differs")
if problems:
    print("; ".join(problems))
    raise SystemExit(1)
PY
)"; then
    pass "Android main pins the canonical contract, fixtures, provenance, and release train"
  else
    fail "Android main is not ready for production promotion: $validation_error"
  fi
}

validate_capabilities() {
  local payload_file="$1"
  local expected_release="$2"
  local fixture_file="${3:-$repo_root/backend/worker/contract/v2/fixtures/capabilities.json}"
  python3 - "$payload_file" "$expected_release" "$fixture_file" <<'PY'
import json
import sys

path, expected_release, fixture_path = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    with open(fixture_path, encoding="utf-8") as handle:
        expected = json.load(handle)
except Exception as error:
    print(f"invalid JSON: {error}")
    raise SystemExit(1)

problems = []
if value.get("api_version") != expected.get("api_version"):
    problems.append(f"api_version is not {expected.get('api_version')}")
if value.get("release_train") != expected_release:
    problems.append(f"release_train is {value.get('release_train')!r}, expected {expected_release!r}")
for group_name in ("catalog", "account"):
    group = value.get(group_name)
    expected_group = expected.get(group_name)
    if not isinstance(group, dict):
        problems.append(f"{group_name} is missing")
        continue
    if not isinstance(expected_group, dict):
        problems.append(f"canonical {group_name} fixture is invalid")
        continue
    mismatched = sorted(name for name, expected_value in expected_group.items() if group.get(name) is not expected_value)
    if mismatched:
        problems.append(f"{group_name} capabilities differ from the canonical fixture: {', '.join(mismatched)}")

languages = value.get("supported_languages")
expected_languages = expected.get("supported_languages")
if not isinstance(languages, list) or not isinstance(expected_languages, list) or len(languages) != len(set(languages)) or set(languages) != set(expected_languages):
    problems.append("supported_languages does not match the six-locale contract")
entities = value.get("supported_entity_kinds")
expected_entities = expected.get("supported_entity_kinds")
if not isinstance(entities, list) or not isinstance(expected_entities, list) or len(entities) != len(set(entities)) or set(entities) != set(expected_entities):
    problems.append("supported_entity_kinds does not match the entity contract")
adult = value.get("adult_content")
expected_adult = expected.get("adult_content")
if not isinstance(adult, dict) or not isinstance(expected_adult, dict) or any(adult.get(name) is not expected_value for name, expected_value in expected_adult.items()):
    problems.append("adult_content policy does not match the local opt-in contract")

if problems:
    print("; ".join(problems))
    raise SystemExit(1)
PY
}

check_environment_endpoint() {
  local environment="$1"
  local base_url="$2"
  local phase="$3"
  local body_file="$preflight_temp_dir/$environment-capabilities.json"
  local headers_file="$preflight_temp_dir/$environment-headers.txt"
  local error_file="$preflight_temp_dir/$environment-curl-error.txt"
  local status
  local validation_error
  local worker_version

  if ! status="$(curl --silent --show-error --max-time 20 \
      --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' \
      "$base_url/v2/capabilities" 2>"$error_file")"; then
    fail "$environment Worker is unavailable at $base_url: $(tail -n 1 "$error_file")"
    return
  fi
  if [[ "$phase" == "prerequisites" ]]; then
    if [[ "$status" == 5* ]]; then
      fail "$environment DNS/TLS is reachable but the endpoint returned HTTP $status"
    else
      pass "$environment DNS/TLS is reachable at $base_url (HTTP $status)"
    fi
    return
  fi
  if [[ "$status" != "200" ]]; then
    fail "$environment capabilities returned HTTP $status"
    return
  fi
  if validation_error="$(validate_capabilities "$body_file" "$expected_release" 2>&1)"; then
    pass "$environment /v2/capabilities matches release $expected_release"
  else
    fail "$environment /v2/capabilities is not release-ready: $validation_error"
  fi

  worker_version="$(tr -d '\r' <"$headers_file" | awk -F': *' 'tolower($1) == "x-smartmovie-worker-version" { print $2; exit }')"
  if [[ "$worker_version" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    pass "$environment exposes a Cloudflare Worker version identifier"
  else
    fail "$environment response has an invalid X-SmartMovie-Worker-Version"
  fi
}

check_local_cloudflare_auth() {
  local output
  if ! command -v npx >/dev/null 2>&1; then
    warn "npx is unavailable; local Wrangler authentication was not checked"
    return
  fi
  output="$(python3 - "$repo_root/backend/worker" <<'PY'
import subprocess
import sys

try:
    completed = subprocess.run(
        ["npx", "--no-install", "wrangler", "whoami"],
        cwd=sys.argv[1],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    print(completed.stdout + completed.stderr)
except subprocess.TimeoutExpired:
    print("SMARTMOVIE_WRANGLER_AUTH_TIMEOUT")
PY
)"
  if printf '%s\n' "$output" | grep -Fq "SMARTMOVIE_WRANGLER_AUTH_TIMEOUT"; then
    warn "Wrangler authentication check timed out after 15 seconds"
  elif printf '%s\n' "$output" | grep -Fqi "not authenticated"; then
    warn "Wrangler is not authenticated locally; use the protected GitHub workflow or run wrangler login"
  elif printf '%s\n' "$output" | grep -Eqi "logged in|account (name|id)"; then
    pass "Wrangler is authenticated for manual Cloudflare operations"
  else
    warn "Wrangler authentication could not be determined"
  fi
}

cleanup_preflight_temp_dir() {
  local expected_prefix="${TMPDIR:-/tmp}/smartmovie-release-preflight."
  if [[ -z "${preflight_temp_dir:-}" || ! -d "$preflight_temp_dir" || "$preflight_temp_dir" != "$expected_prefix"* ]]; then
    return
  fi
  rm -f \
    "$preflight_temp_dir/staging-capabilities.json" \
    "$preflight_temp_dir/staging-headers.txt" \
    "$preflight_temp_dir/staging-curl-error.txt" \
    "$preflight_temp_dir/production-capabilities.json" \
    "$preflight_temp_dir/production-headers.txt" \
    "$preflight_temp_dir/production-curl-error.txt" \
    "$preflight_temp_dir/android-contract-manifest.json" \
    "$preflight_temp_dir/android-release-train.json"
  rmdir "$preflight_temp_dir" 2>/dev/null || true
}

main() {
  local scope="all"
  local phase="prerequisites"
  local commands_ready=0
  local command_name
  local expected_release

  if (( $# > 2 )); then
    printf 'Usage: %s [all|staging|production] [--live]\n' "$0" >&2
    return 2
  fi
  if (( $# >= 1 )); then
    scope="$1"
  fi
  if (( $# == 2 )); then
    phase="$2"
  fi

  case "$scope" in
    all|staging|production) ;;
    *)
      printf 'Usage: %s [all|staging|production] [--live]\n' "$0" >&2
      return 2
      ;;
  esac
  case "$phase" in
    prerequisites) ;;
    --live) phase="live" ;;
    *)
      printf 'Usage: %s [all|staging|production] [--live]\n' "$0" >&2
      return 2
      ;;
  esac
  check_source_release

  for command_name in gh curl python3; do
    if require_command "$command_name"; then
      commands_ready=$((commands_ready + 1))
    fi
  done

  expected_release="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["train_version"])' "$repo_root/release/train.json" 2>/dev/null || true)"
  if [[ -z "$expected_release" ]]; then
    fail "release/train.json does not contain train_version"
  fi

  if (( commands_ready == 3 )) && [[ -n "$expected_release" ]]; then
    if preflight_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/smartmovie-release-preflight.XXXXXX")"; then
      trap cleanup_preflight_temp_dir EXIT
      if gh auth status --hostname github.com >/dev/null 2>&1; then
        pass "GitHub CLI is authenticated"
        check_repository_secrets
        if [[ "$scope" == "all" || "$scope" == "staging" ]]; then
          check_environment_secrets staging
        fi
        if [[ "$scope" == "all" || "$scope" == "production" ]]; then
          check_environment_secrets production
          check_production_environment_protection
          check_android_main_contract
        fi
      else
        fail "GitHub CLI is not authenticated"
      fi
      if [[ "$scope" == "all" || "$scope" == "staging" ]]; then
        check_environment_endpoint staging "https://staging-catalog.smartmovie.app" "$phase"
      fi
      if [[ "$scope" == "all" || "$scope" == "production" ]]; then
        check_environment_endpoint production "https://catalog.smartmovie.app" "$phase"
      fi
    else
      preflight_temp_dir=""
      fail "could not create a private temporary directory for endpoint validation"
    fi
  fi

  check_local_cloudflare_auth

  if (( failures > 0 )); then
    printf '\nRelease preflight found %d blocking issue(s) and %d warning(s). No deployment, secret, DNS, D1 schema, or account data was changed.\n' "$failures" "$warnings"
    return 1
  fi

  printf '\nRelease preflight passed with %d warning(s). No deployment, secret, DNS, D1 schema, or account data was changed.\n' "$warnings"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
