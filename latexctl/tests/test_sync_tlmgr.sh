#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local expected="$2"

  grep -Fx "$expected" "$file" >/dev/null 2>&1 || fail "expected '$expected' in $file"
}

assert_log_contains() {
  local file="$1"
  local expected="$2"

  grep -F "$expected" "$file" >/dev/null 2>&1 || fail "expected '$expected' in $file"
}

assert_log_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -F "$unexpected" "$file" >/dev/null 2>&1; then
    fail "did not expect '$unexpected' in $file"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  if grep -Fx "$unexpected" "$file" >/dev/null 2>&1; then
    fail "did not expect '$unexpected' in $file"
  fi
}

assert_file_exists() {
  local file="$1"

  [[ -f "$file" ]] || fail "expected file to exist: $file"
}

assert_command_fails() {
  local output_file="$1"
  shift

  if "$@" >"$output_file" 2>&1; then
    fail "expected command to fail: $*"
  fi
}

setup_sandbox() {
  local fixture="$1"
  local sandbox
  sandbox="$(mktemp -d)"

  mkdir -p \
    "$sandbox/repo/scripts" \
    "$sandbox/repo/tex" \
    "$sandbox/bin" \
    "$sandbox/logs" \
    "$sandbox/state" \
    "$sandbox/home" \
    "$sandbox/texmf-home/tlpkg"

  cp -R "${REPO_ROOT}/latexctl" "$sandbox/repo/latexctl"
  rm -f "$sandbox/repo/latexctl/package-overrides.conf"
  ln -s "${REPO_ROOT}/Makefile" "$sandbox/repo/Makefile"
  cp -R "${REPO_ROOT}/latexctl/tests/fixtures/${fixture}/tex/." "$sandbox/repo/tex/"

  : > "$sandbox/texmf-home/tlpkg/texlive.tlpdb"

  cat > "$sandbox/bin/tlmgr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TLMGR_LOG:?}"
: "${TLMGR_STATE:?}"

mkdir -p "$(dirname "$TLMGR_LOG")" "$(dirname "$TLMGR_STATE")"
printf 'tlmgr %s\n' "$*" >> "$TLMGR_LOG"

mark_installed() {
  local package="$1"
  grep -Fxq "$package" "$TLMGR_STATE" 2>/dev/null || printf '%s\n' "$package" >> "$TLMGR_STATE"
}

is_installed() {
  local package="$1"
  grep -Fxq "$package" "$TLMGR_STATE" 2>/dev/null
}

case "${1:-}" in
  info)
    if [[ "${2:-}" == "--only-installed" && $# -eq 2 ]]; then
      while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        printf 'package:     %s\n' "$package"
      done < "$TLMGR_STATE"
      exit 0
    fi

    if [[ "${2:-}" == "biblatex" ]]; then
      printf 'package:     biblatex\ncategory:    Package\n'
      exit 0
    fi

    if [[ "${2:-}" == "logreq" ]]; then
      exit 1
    fi

    if [[ "${2:-}" == "pathreq" ]]; then
      exit 1
    fi

    if [[ "${2:-}" == "--only-installed" && "${3:-}" == "biber" ]]; then
      if is_installed "biber"; then
        printf 'package:     biber\n'
        exit 0
      fi
      exit 1
    fi

    if [[ "${2:-}" == "memoir" ]]; then
      exit 1
    fi

    exit 1
    ;;
  search)
    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/memoir.cls" ]]; then
      case "${TLMGR_SEARCH_MODE:-default}" in
        ambiguous)
          printf 'memoir-alt:\n\ttexmf-dist/tex/latex/memoir/memoir.cls\n'
          printf 'memoir-doc:\n\ttexmf-dist/doc/latex/memoir/memoir.cls\n'
          printf 'memoir-src:\n\ttexmf-dist/source/latex/memoir/memoir.cls\n'
          printf 'memoir-other:\n\ttexmf-dist/tex/latex/memoir/memoir.cls\n'
          ;;
        default|docsrc)
          printf 'memoir-doc:\n\ttexmf-dist/doc/latex/memoir/memoir.cls\n'
          printf 'memoir-src:\n\ttexmf-dist/source/latex/memoir/memoir.cls\n'
          printf 'memoir:\n\ttexmf-dist/tex/latex/memoir/memoir.cls\n'
          ;;
        *)
          exit 1
          ;;
      esac
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/ts1-qtmr" ]]; then
      printf 'tex-gyre:\n\ttexmf-dist/fonts/tfm/public/tex-gyre/ts1-qtmr.tfm\n'
      printf 'tex4ht:\n\ttexmf-dist/tex4ht/ht-fonts/alias/TeXGyreTermes/ts1-qtmr.htf\n'
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/ts1-qtmr\\..*" ]]; then
      printf 'tex-gyre:\n\ttexmf-dist/fonts/tfm/public/tex-gyre/ts1-qtmr.tfm\n'
      printf 'tex4ht:\n\ttexmf-dist/tex4ht/ht-fonts/alias/TeXGyreTermes/ts1-qtmr.htf\n'
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/pcrr8t" ]]; then
      printf 'courier:\n\ttexmf-dist/fonts/vf/adobe/courier/pcrr8t.vf\n'
      printf 'courier:\n\ttexmf-dist/fonts/tfm/adobe/courier/pcrr8t.tfm\n'
      printf 'pslatex:\n\ttexmf-dist/fonts/vf/public/pslatex/pcrr8tn.vf\n'
      printf 'pslatex:\n\ttexmf-dist/fonts/tfm/public/pslatex/pcrr8tn.tfm\n'
      printf 'tex4ht:\n\ttexmf-dist/tex4ht/ht-fonts/alias/adobe/courier/pcrr8t.htf\n'
      printf 'tex4ht:\n\ttexmf-dist/tex4ht/ht-fonts/alias/adobe/pslatex/pcrr8tn.htf\n'
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/pcrr8t\\..*" ]]; then
      printf 'courier:\n\ttexmf-dist/fonts/vf/adobe/courier/pcrr8t.vf\n'
      printf 'courier:\n\ttexmf-dist/fonts/tfm/adobe/courier/pcrr8t.tfm\n'
      printf 'tex4ht:\n\ttexmf-dist/tex4ht/ht-fonts/alias/adobe/courier/pcrr8t.htf\n'
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/logreq.sty" ]]; then
      printf 'logreq:\n\ttexmf-dist/tex/latex/logreq/logreq.sty\n'
      exit 0
    fi

    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/styles/pathreq.sty" ]]; then
      printf 'pathreq:\n\ttexmf-dist/tex/latex/pathreq/pathreq.sty\n'
      exit 0
    fi

    exit 1
    ;;
  --usermode)
    if [[ "${2:-}" == "install" ]]; then
      shift 2
      for package in "$@"; do
        mark_installed "$package"
      done
      exit 0
    fi
    exit 0
    ;;
  install)
    shift
    for package in "$@"; do
      mark_installed "$package"
    done
    exit 0
    ;;
  init-usertree)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$sandbox/bin/tlmgr"

  cat > "$sandbox/bin/kpsewhich" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TLMGR_LOG:?}"
mkdir -p "$(dirname "$TLMGR_LOG")"
printf 'kpsewhich %s\n' "$*" >> "$TLMGR_LOG"

case "${1:-}" in
  article.cls)
    printf '/usr/local/texlive/texmf-dist/tex/latex/base/article.cls\n'
    ;;
  biblatex.sty)
    exit 1
    ;;
  memoir.cls)
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$sandbox/bin/kpsewhich"

  cat > "$sandbox/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TLMGR_LOG:?}"
mkdir -p "$(dirname "$TLMGR_LOG")"
printf 'sudo %s\n' "$*" >> "$TLMGR_LOG"
exec "$@"
EOF
  chmod +x "$sandbox/bin/sudo"
  printf '%s\n' "$sandbox"
}

run_basic_biblatex_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  assert_file_contains "$sandbox/repo/.used_packages" "biblatex"
  assert_file_contains "$sandbox/repo/.used_tools" "biber"
  assert_log_contains "$sandbox/logs/tlmgr.log" "sudo tlmgr install biber"
)

run_tool_override_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  mkdir -p "$sandbox/repo/tools"
  cat > "$sandbox/repo/extra-tools.txt" <<'EOF'
# repo-local tool overrides
latexindent
chktex
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export TLMGR_SEARCH_MODE="docsrc"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  assert_file_contains "$sandbox/repo/.used_tools" "chktex"
  assert_file_contains "$sandbox/repo/.used_tools" "latexindent"
  assert_file_not_contains "$sandbox/repo/.used_packages" "chktex"
  assert_file_not_contains "$sandbox/repo/.used_packages" "latexindent"
  assert_log_contains "$sandbox/logs/tlmgr.log" "sudo tlmgr install chktex latexindent"
)

run_tool_override_without_sources_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  find "$sandbox/repo/tex" -type f -delete

  mkdir -p "$sandbox/repo/tools"
  cat > "$sandbox/repo/extra-tools.txt" <<'EOF'
# tool-only bootstrap repo
latexindent
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  if [[ -s "$sandbox/repo/.used_packages" ]]; then
    fail "expected no package entries for empty tex tree"
  fi
  assert_file_contains "$sandbox/repo/.used_tools" "latexindent"
  assert_log_contains "$sandbox/logs/tlmgr.log" "sudo tlmgr install latexindent"
)

run_documentclass_resolution_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export TLMGR_SEARCH_MODE="docsrc"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  assert_file_contains "$sandbox/repo/.used_packages" "memoir"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /memoir.cls"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install memoir"
)

run_ambiguous_resolution_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  output_file="$sandbox/logs/failure.log"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export TLMGR_SEARCH_MODE="ambiguous"

  assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" sync

  assert_log_contains "$output_file" "ambiguous package owner for memoir.cls"
  assert_log_contains "$output_file" "latexctl/package-overrides.conf"
)

run_override_resolution_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/latexctl/package-overrides.conf" <<'EOF'
memoir.cls=memoir-override
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export TLMGR_SEARCH_MODE="ambiguous"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  assert_file_contains "$sandbox/repo/.used_packages" "memoir-override"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install memoir-override"
)

run_font_metric_resolution_prefers_tfm_owner_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  "$sandbox/repo/latexctl/bin/latexctl" sync --resolve-file ts1-qtmr

  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /ts1-qtmr"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install tex-gyre"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install tex4ht"
)

run_font_metric_resolution_filters_prefix_false_positive_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  "$sandbox/repo/latexctl/bin/latexctl" sync --resolve-file pcrr8t

  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /pcrr8t"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install courier"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install pslatex"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install tex4ht"
)

run_local_documentclass_skip_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox local-documentclass)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  "$sandbox/repo/latexctl/bin/latexctl" sync

  if [[ -s "$sandbox/repo/.used_packages" ]]; then
    fail "expected local documentclass to avoid package installation"
  fi
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /ppginf.cls"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install ppginf"
)

run_missing_file_retry_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

if [[ "$count" -eq 1 ]]; then
  cat > tex/main.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
  exit 1
fi
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"
  export MAX_MISSING_FILE_RETRIES="1"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -interaction=nonstopmode -file-line-error tex/main.tex"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "2" ]]; then
    fail "expected latexmk to run exactly twice"
  fi
)

run_missing_file_retry_forces_latexmk_rerun_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

if [[ "$count" -eq 1 ]]; then
  cat > tex/main.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
  exit 1
fi

for arg in "$@"; do
  if [[ "$arg" == "-g" ]]; then
    exit 0
  fi
done

printf '%s\n' "Latexmk: Nothing to do for 'tex/main.tex'." >> "$LATEXMK_LOG"
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"
  export MAX_MISSING_FILE_RETRIES="1"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -interaction=nonstopmode -file-line-error tex/main.tex"
  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -g -interaction=nonstopmode -file-line-error tex/main.tex"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "2" ]]; then
    fail "expected forced-rerun scenario to run latexmk exactly twice"
  fi
)

run_build_cleans_once_archives_pdf_and_records_retry_install_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  mkdir -p "$sandbox/repo/0-iniciais"
  cat > "$sandbox/repo/tex/main.aux" <<'EOF'
stale aux
EOF
  cat > "$sandbox/repo/tex/main.pdf" <<'EOF'
old pdf
EOF
  touch -d '2024-01-02 03:04:05 UTC' "$sandbox/repo/tex/main.pdf"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

if [[ "$count" -eq 1 ]]; then
  if [[ -f tex/main.aux ]]; then
    printf '%s\n' "tex/main.aux should have been cleaned before first build" >> "$LATEXMK_LOG"
    exit 1
  fi

  cat > tex/main.aux <<'AUX'
fresh aux
AUX
  cat > tex/main.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
  exit 1
fi

if [[ ! -f tex/main.aux ]]; then
  printf '%s\n' "tex/main.aux should persist across retry attempts" >> "$LATEXMK_LOG"
  exit 1
fi

cat > tex/main.pdf <<'PDF'
new pdf
PDF
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_file_exists "$sandbox/repo/tex/main.pdf"
  assert_file_exists "$sandbox/repo/tex/main.previous.pdf"
  assert_file_contains "$sandbox/repo/tex/main.previous.pdf" "old pdf"
  assert_file_contains "$sandbox/repo/tex/main.pdf" "new pdf"
  assert_log_contains "$sandbox/repo/.build_retry_installs" "artifact=logreq.sty package=logreq"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "2" ]]; then
    fail "expected clean-and-archive scenario to run latexmk exactly twice"
  fi
)

run_zero_retry_missing_file_failure_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

cat > tex/main.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -interaction=nonstopmode -file-line-error tex/main.tex"
  assert_log_contains "$output_file" "persistent missing environment asset"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "2" ]]; then
    fail "expected latexmk to run twice before detecting persistent missing asset"
  fi
)

run_relocated_log_retry_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

if [[ "$count" -eq 1 ]]; then
  mkdir -p tex/build
  cat > tex/build/paper.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
  exit 1
fi
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex "-outdir=build" "-jobname=paper"
  )

  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "2" ]]; then
    fail "expected relocated-log retry to run latexmk exactly twice"
  fi
)

run_local_basename_missing_file_failure_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/repo/tex/logreq.sty" <<'EOF'
\ProvidesPackage{logreq}
\endinput
EOF

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

cat > tex/main.log <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$output_file" "local-project missing file"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "1" ]]; then
    fail "expected local basename missing-file failure to stop after one latexmk run"
  fi
)

run_pathful_missing_file_failure_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

cat > tex/main.log <<'LOG'
! LaTeX Error: File `styles/pathreq.sty' not found.
LOG
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$output_file" "local-project missing file"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /styles/pathreq.sty"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install pathreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "1" ]]; then
    fail "expected pathful missing-file failure to stop after one latexmk run"
  fi
)

run_latexmk_quoted_arg_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
mkdir -p "$(dirname "$LATEXMK_LOG")"

for arg in "$@"; do
  printf 'arg:%s\n' "$arg" >> "$LATEXMK_LOG"
done
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex "-jobname=chapter draft"
  )

  assert_log_contains "$sandbox/logs/latexmk.log" "arg:-jobname=chapter draft"
)

run_build_sets_local_search_paths_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox local-documentclass)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/tex/referencias.bib" <<'EOF'
@book{demo,
  title = {Demo}
}
EOF

  cat > "$sandbox/repo/tex/apalike-ptbr.bst" <<'EOF'
ENTRY{}{}{}
READ
EOF

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
mkdir -p "$(dirname "$LATEXMK_LOG")"

printf 'TEXINPUTS=%s\n' "${TEXINPUTS:-}" >> "$LATEXMK_LOG"
printf 'BIBINPUTS=%s\n' "${BIBINPUTS:-}" >> "$LATEXMK_LOG"
printf 'BSTINPUTS=%s\n' "${BSTINPUTS:-}" >> "$LATEXMK_LOG"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"

  (
    cd "$sandbox/repo"
    "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$sandbox/logs/latexmk.log" "TEXINPUTS=$sandbox/repo/tex//:"
  assert_log_contains "$sandbox/logs/latexmk.log" "BIBINPUTS=$sandbox/repo/tex//:"
  assert_log_contains "$sandbox/logs/latexmk.log" "BSTINPUTS=$sandbox/repo/tex//:"
)

run_non_tex_missing_file_failure_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

cat > tex/main.log <<'LOG'
! LaTeX Error: File `diagram.png' not found.
LOG
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$output_file" "local-project missing file diagram.png"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /diagram.png"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install diagram"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "1" ]]; then
    fail "expected latexmk to run exactly once for non-TeX missing files"
  fi
)

run_stale_log_is_ignored_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  mkdir -p "$sandbox/repo/tex"
  cat > "$sandbox/repo/tex/main.log" <<'LOG'
! LaTeX Error: File `logreq.sty' not found.
LOG
  touch -d '2000-01-01 00:00:00' "$sandbox/repo/tex/main.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
: "${LATEXMK_COUNT_FILE:?}"

mkdir -p "$(dirname "$LATEXMK_LOG")" "$(dirname "$LATEXMK_COUNT_FILE")"

count="$(cat "$LATEXMK_COUNT_FILE" 2>/dev/null || printf '0')"
count="$((count + 1))"
printf '%s' "$count" > "$LATEXMK_COUNT_FILE"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"

exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"
  export LATEXMK_COUNT_FILE="$sandbox/logs/latexmk-count"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_log_contains "$output_file" "without a discoverable log file"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr search --global --file /logreq.sty"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install logreq"
  if [[ "$(cat "$sandbox/logs/latexmk-count")" != "1" ]]; then
    fail "expected stale-log scenario to stop after one latexmk run"
  fi
)

run_make_build_skips_lint_tool_preflight_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox documentclass-miss)"
  trap 'rm -rf "$sandbox"' EXIT

  mkdir -p "$sandbox/repo/tools"
  cat > "$sandbox/repo/extra-tools.txt" <<'EOF'
chktex
latexindent
EOF

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
mkdir -p "$(dirname "$LATEXMK_LOG")"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:/usr/bin:/bin"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export TLMGR_SEARCH_MODE="docsrc"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"

  (
    cd "$sandbox/repo"
    make build
  )

  assert_log_contains "$sandbox/logs/tlmgr.log" "sudo tlmgr install chktex latexindent"
  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -interaction=nonstopmode -file-line-error tex/main.tex"
)

run_make_clean_keeps_pdf_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox local-documentclass)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/tex/main.pdf" <<'EOF'
compiled pdf
EOF
  cat > "$sandbox/repo/tex/main.aux" <<'EOF'
compiled aux
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:/usr/bin:/bin"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  (
    cd "$sandbox/repo"
    make clean
  )

  assert_file_exists "$sandbox/repo/tex/main.pdf"
  if [[ -f "$sandbox/repo/tex/main.aux" ]]; then
    fail "expected make clean to remove tex/main.aux"
  fi
)

run_make_pdf_bypasses_smart_build_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox local-documentclass)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
mkdir -p "$(dirname "$LATEXMK_LOG")"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:/usr/bin:/bin"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"

  (
    cd "$sandbox/repo"
    make pdf
  )

  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -interaction=nonstopmode -file-line-error tex/main.tex"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "tlmgr --usermode install"
  assert_log_not_contains "$sandbox/logs/tlmgr.log" "kpsewhich"
  assert_file_exists "$sandbox/repo/build-report.md"
  assert_file_contains "$sandbox/repo/build-report.md" "# LaTeX Build Report"
  assert_log_contains "$sandbox/repo/build-report.md" "Status: \`success\`"
)

run_make_watch_sets_local_search_paths_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox local-documentclass)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LATEXMK_LOG:?}"
mkdir -p "$(dirname "$LATEXMK_LOG")"

printf 'TEXINPUTS=%s\n' "${TEXINPUTS:-}" >> "$LATEXMK_LOG"
printf 'latexmk %s\n' "$*" >> "$LATEXMK_LOG"
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:/usr/bin:/bin"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"
  export LATEXMK_LOG="$sandbox/logs/latexmk.log"

  (
    cd "$sandbox/repo"
    make watch
  )

  assert_log_contains "$sandbox/logs/latexmk.log" "TEXINPUTS=$sandbox/repo/tex//:"
  assert_log_contains "$sandbox/logs/latexmk.log" "latexmk -cd -pdf -pvc -interaction=nonstopmode -file-line-error tex/main.tex"
)

run_basic_biblatex_test
run_tool_override_test
run_tool_override_without_sources_test
run_documentclass_resolution_test
run_ambiguous_resolution_test
run_override_resolution_test
run_font_metric_resolution_prefers_tfm_owner_test
run_font_metric_resolution_filters_prefix_false_positive_test
run_local_documentclass_skip_test
run_missing_file_retry_test
run_missing_file_retry_forces_latexmk_rerun_test
run_build_cleans_once_archives_pdf_and_records_retry_install_test
run_zero_retry_missing_file_failure_test
run_relocated_log_retry_test
run_local_basename_missing_file_failure_test
run_pathful_missing_file_failure_test
run_latexmk_quoted_arg_test
run_build_sets_local_search_paths_test
run_non_tex_missing_file_failure_test
run_stale_log_is_ignored_test
run_make_build_skips_lint_tool_preflight_test
run_make_clean_keeps_pdf_test
run_make_pdf_bypasses_smart_build_test
run_make_watch_sets_local_search_paths_test

echo "PASS: test_sync_tlmgr"
