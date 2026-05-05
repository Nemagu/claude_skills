#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run_pytest_guard.sh [quick|full|cov|changed] [target] [-- <extra pytest args>]

Examples:
  run_pytest_guard.sh quick src/tests/unit
  run_pytest_guard.sh full
  run_pytest_guard.sh cov src/tests -- -k "not slow"
  run_pytest_guard.sh changed
  run_pytest_guard.sh changed src/tests/unit

Environment:
  COV_TARGET               Module/package for coverage in cov mode (default: src)
  CHANGED_BASE             Git base for changed mode (default: HEAD)
  CHANGED_INCLUDE_UNTRACKED 1 to include untracked files, 0 to skip (default: 1)
  CHANGED_FALLBACK         quick|full|cov|none when no impacted tests found (default: quick)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

MODE="${1:-quick}"
shift || true

TARGET=""
if [[ $# -gt 0 && "${1:-}" != "--" ]]; then
  TARGET="$1"
  shift
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

EXTRA_ARGS=("$@")

case "$MODE" in
  quick|full|cov|changed) ;;
  *)
    echo "[guard] Unknown mode: $MODE" >&2
    usage
    exit 2
    ;;
esac

if ! command -v uv >/dev/null 2>&1 && ! command -v pytest >/dev/null 2>&1; then
  echo "[guard] pytest or uv is required in PATH" >&2
  exit 3
fi

if command -v uv >/dev/null 2>&1; then
  RUN=(uv run pytest)
else
  RUN=(pytest)
fi

if ! "${RUN[@]}" --version >/dev/null 2>&1; then
  echo "[guard] Unable to execute pytest via selected runner" >&2
  exit 4
fi

TESTS_ROOT=""
if [[ -d "tests" ]]; then
  TESTS_ROOT="tests"
elif [[ -d "src/tests" ]]; then
  TESTS_ROOT="src/tests"
fi

if [[ -z "$TESTS_ROOT" ]]; then
  echo "[guard] tests directory not found (expected tests/ or src/tests/)" >&2
  exit 5
fi

if [[ -z "$TARGET" ]]; then
  TARGET="$TESTS_ROOT"
fi

if [[ ! -e "$TARGET" ]]; then
  echo "[guard] target does not exist: $TARGET" >&2
  exit 6
fi

COV_TARGET="${COV_TARGET:-src}"

run_mode() {
  local mode="$1"
  case "$mode" in
    quick)
      CMD=("${RUN[@]}" -q "$TARGET" "${EXTRA_ARGS[@]}")
      ;;
    full)
      CMD=("${RUN[@]}" "$TARGET" "${EXTRA_ARGS[@]}")
      ;;
    cov)
      if ! "${RUN[@]}" --help | grep -q -- "--cov"; then
        echo "[guard] pytest-cov plugin is not available" >&2
        exit 7
      fi
      CMD=("${RUN[@]}" "$TARGET" --cov="$COV_TARGET" --cov-report=term-missing "${EXTRA_ARGS[@]}")
      ;;
    *)
      echo "[guard] Unsupported mode in run_mode: $mode" >&2
      exit 8
      ;;
  esac

  echo "[guard] mode=$mode target=$TARGET"
  echo "[guard] runner=${RUN[*]}"
  if [[ "$mode" == "cov" ]]; then
    echo "[guard] cov_target=$COV_TARGET"
  fi
  "${CMD[@]}"
}

run_changed_mode() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[guard] git is required for changed mode" >&2
    exit 9
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[guard] changed mode requires running inside a git repository" >&2
    exit 10
  fi

  local base="${CHANGED_BASE:-HEAD}"
  local include_untracked="${CHANGED_INCLUDE_UNTRACKED:-1}"
  local fallback="${CHANGED_FALLBACK:-quick}"

  mapfile -t changed_files < <(
    {
      git diff --name-only "$base" --
      git diff --cached --name-only --
      if [[ "$include_untracked" == "1" ]]; then
        git ls-files --others --exclude-standard
      fi
    } | sed '/^$/d' | sort -u
  )

  if [[ ${#changed_files[@]} -eq 0 ]]; then
    echo "[guard] no changed files detected"
    if [[ "$fallback" == "none" ]]; then
      exit 0
    fi
    run_mode "$fallback"
    return
  fi

  declare -A selected=()
  local path=""
  local stem=""

  for path in "${changed_files[@]}"; do
    if [[ "$path" == "$TESTS_ROOT"/*.py || "$path" == *.py && "$path" == *"/tests/"* ]]; then
      if [[ -f "$path" ]]; then
        selected["$path"]=1
      fi
      continue
    fi

    if [[ "$path" != *.py ]]; then
      continue
    fi

    stem="${path##*/}"
    stem="${stem%.py}"

    while IFS= read -r candidate; do
      [[ -n "$candidate" && -f "$candidate" ]] && selected["$candidate"]=1
    done < <(find "$TESTS_ROOT" -type f \( -name "test_${stem}.py" -o -name "${stem}_test.py" \) 2>/dev/null)
  done

  mapfile -t selected_tests < <(printf '%s\n' "${!selected[@]}" | sed '/^$/d' | sort -u)

  if [[ ${#selected_tests[@]} -eq 0 ]]; then
    echo "[guard] impacted tests not resolved from changed files"
    if [[ "$fallback" == "none" ]]; then
      exit 0
    fi
    run_mode "$fallback"
    return
  fi

  echo "[guard] mode=changed base=$base tests=${#selected_tests[@]}"
  echo "[guard] runner=${RUN[*]}"
  "${RUN[@]}" -q "${selected_tests[@]}" "${EXTRA_ARGS[@]}"
}

if [[ "$MODE" == "changed" ]]; then
  run_changed_mode
else
  run_mode "$MODE"
fi
