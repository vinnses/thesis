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

  if [[ ! -f "$file" ]]; then
    cat "$output_file" 2>/dev/null || true
    fail "missing file: $file"
  fi
  grep -F "$expected" "$file" >/dev/null 2>&1 || fail "expected '$expected' in $file"
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"

  [[ -f "$file" ]] || return 0
  if grep -F "$unexpected" "$file" >/dev/null 2>&1; then
    fail "did not expect '$unexpected' in $file"
  fi
}

assert_file_exists() {
  local file="$1"

  [[ -f "$file" ]] || fail "expected file to exist: $file"
}

assert_dir_exists() {
  local dir="$1"

  [[ -d "$dir" ]] || fail "expected directory to exist: $dir"
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
    "$sandbox/repo/tests" \
    "$sandbox/repo/tex" \
    "$sandbox/bin" \
    "$sandbox/logs" \
    "$sandbox/state" \
    "$sandbox/home" \
    "$sandbox/texmf-home/tlpkg"

  cp -R "${REPO_ROOT}/latexctl" "$sandbox/repo/latexctl"
  rm -f "$sandbox/repo/latexctl/package-overrides.conf"
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

    exit 1
    ;;
  search)
    if [[ "${2:-}" == "--global" && "${3:-}" == "--file" && "${4:-}" == "/logreq.sty" ]]; then
      printf 'logreq:\n\ttexmf-dist/tex/latex/logreq/logreq.sty\n'
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

case "${1:-}" in
  article.cls)
    printf '/usr/local/texlive/texmf-dist/tex/latex/base/article.cls\n'
    ;;
  biblatex.sty)
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
exec "$@"
EOF
  chmod +x "$sandbox/bin/sudo"

  printf '%s\n' "$sandbox"
}

run_missing_tex_package_classification_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/main.log" <<'EOF'
! LaTeX Error: File `logreq.sty' not found.
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl classify-error --log main.log --output-dir .latex-errors
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=environment"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "kind=missing_tex_asset"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "artifact=logreq.sty"
  assert_file_contains "$sandbox/repo/.latex-errors/environment-errors.log" "logreq.sty"
  assert_file_not_contains "$sandbox/repo/.latex-errors/user-errors.log" "logreq.sty"
)

run_missing_local_asset_classification_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/main.log" <<'EOF'
! LaTeX Error: File `diagram.png' not found.
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl classify-error --log main.log --output-dir .latex-errors
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=user"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "kind=missing_local_asset"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "artifact=diagram.png"
  assert_file_contains "$sandbox/repo/.latex-errors/user-errors.log" "diagram.png"
  assert_file_not_contains "$sandbox/repo/.latex-errors/environment-errors.log" "diagram.png"
)

run_missing_pathful_local_file_classification_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/main.log" <<'EOF'
! LaTeX Error: File `1-intro/texto.tex' not found.
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl classify-error --log main.log --output-dir .latex-errors
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=user"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "kind=missing_local_input"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "artifact=1-intro/texto.tex"
)

run_missing_font_metric_classification_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/main.log" <<'EOF'
kpathsea: Running mktextfm ts1-qtmr
Font TS1/ntxtlf/m/n/12=ts1-qtmr at 12.0pt not loadable: Metric (TFM) file not found.
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl classify-error --log main.log --output-dir .latex-errors
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=environment"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "kind=missing_font_metric"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "artifact=ts1-qtmr"
  assert_file_contains "$sandbox/repo/.latex-errors/environment-errors.log" "ts1-qtmr"
)

run_unicode_character_classification_test() (
  set -euo pipefail

  local sandbox
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/main.log" <<'EOF'
./main.toc:20: LaTeX Error: Unicode character  (U+009A)
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl classify-error --log main.log --output-dir .latex-errors
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=user"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "kind=unicode_character"
  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "artifact=U+009A"
  assert_file_contains "$sandbox/repo/.latex-errors/user-errors.log" "Unicode character"
)

run_build_writes_user_error_report_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 1
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

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=user"
  assert_file_contains "$sandbox/repo/.latex-errors/user-errors.log" "diagram.png"
  assert_file_contains "$output_file" "See .latex-errors/user-errors.log"
)

run_build_writes_environment_error_report_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 1
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

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_file_contains "$sandbox/repo/.latex-errors/summary.env" "scope=environment"
  assert_file_contains "$sandbox/repo/.latex-errors/environment-errors.log" "logreq.sty"
  assert_file_contains "$output_file" "See .latex-errors/environment-errors.log"
)

run_build_writes_markdown_report_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/build-failure.log"

  cat > "$sandbox/bin/latexmk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 1
cat > tex/main.log <<'LOG'
Package hyperref Warning: Token not allowed in a PDF string (Unicode):
(hyperref)                removing `\alpha' on input line 7.
Package lipsum Warning: Unknown language 'latin'. Hyphenation patterns for
(lipsum)                language 'english' will be used instead.
! LaTeX Error: Unicode character  (U+009A)
l.42 \section{Bad  title}
LOG
exit 1
EOF
  chmod +x "$sandbox/bin/latexmk"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export TLMGR_LOG="$sandbox/logs/tlmgr.log"
  export TLMGR_STATE="$sandbox/state/installed.txt"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" "$sandbox/repo/latexctl/bin/latexctl" build tex/main.tex
  )

  assert_file_exists "$sandbox/repo/.latex-errors/errors.log"
  assert_file_exists "$sandbox/repo/.latex-errors/warnings.log"
  assert_file_contains "$sandbox/repo/build-report.md" "# LaTeX Build Report"
  assert_file_contains "$sandbox/repo/build-report.md" "Error count: \`1\`"
  assert_file_contains "$sandbox/repo/build-report.md" "Warning count: \`2\`"
  assert_file_contains "$sandbox/repo/build-report.md" ".latex-errors/errors.log"
  assert_file_contains "$sandbox/repo/build-report.md" ".latex-errors/warnings.log"
  assert_file_not_contains "$sandbox/repo/build-report.md" "Token not allowed in a PDF string"
  assert_file_not_contains "$sandbox/repo/build-report.md" "! LaTeX Error: Unicode character"
  assert_file_not_contains "$sandbox/repo/build-report.md" "l.42 \\section{Bad"
  assert_file_contains "$sandbox/repo/.latex-errors/errors.log" "Unicode character"
  assert_file_contains "$sandbox/repo/.latex-errors/errors.log" "l.42 \\section{Bad"
  assert_file_contains "$sandbox/repo/.latex-errors/warnings.log" "Token not allowed in a PDF string"
  assert_file_contains "$sandbox/repo/.latex-errors/warnings.log" "removing \`\\alpha'"
  assert_file_contains "$sandbox/repo/.latex-errors/warnings.log" "Unknown language 'latin'"
  assert_file_contains "$sandbox/repo/.latex-errors/warnings.log" "language 'english' will be used instead."
)

run_bootstrap_uses_internal_scaffold_test() (
  set -euo pipefail

  local sandbox
  local output_file
  local real_git
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/bootstrap.log"
  real_git="$(command -v git)"

  rm -rf "$sandbox/repo/tex"
  mkdir -p "$sandbox/repo/tex"

  cat > "$sandbox/bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "clone" ]]; then
  echo "unexpected git clone: \$*" >&2
  exit 99
fi

exec "${real_git}" "\$@"
EOF
  chmod +x "$sandbox/bin/git"

  cat > "$sandbox/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected curl: $*" >&2
exit 98
EOF
  chmod +x "$sandbox/bin/curl"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  unset TEMPLATE_URL

  (
    cd "$sandbox/repo"
    latexctl/bin/latexctl bootstrap >"$output_file" 2>&1
  )

  assert_file_contains "$output_file" "initializing from internal scaffold"
  assert_file_contains "$output_file" "run make build to install dependences"
  assert_file_exists "$sandbox/repo/tex/main.tex"
  assert_file_contains "$sandbox/repo/tex/main.tex" "\\documentclass"
  assert_dir_exists "$sandbox/repo/tex/sections"
)

run_ctan_mirror_uses_env_override_test() (
  set -euo pipefail

  local sandbox
  local output
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  export CTAN_MIRROR="https://example.invalid/custom/tlnet"

  output="$(
    cd "$sandbox/repo"
    latexctl/bin/latexctl ctan-mirror
  )"

  [[ "${output}" == "https://example.invalid/custom/tlnet" ]] || fail "unexpected CTAN mirror override output: ${output}"
)

run_ctan_mirror_uses_first_configured_mirror_test() (
  set -euo pipefail

  local sandbox
  local output
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT

  cat > "$sandbox/repo/latexctl/ctan-mirrors.txt" <<'EOF'
# Preferred explicit mirrors.

https://mirror1.example/tlnet
https://mirror2.example/tlnet
EOF

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"
  unset CTAN_MIRROR

  output="$(
    cd "$sandbox/repo"
    latexctl/bin/latexctl ctan-mirror
  )"

  [[ "${output}" == "https://mirror1.example/tlnet" ]] || fail "unexpected configured CTAN mirror output: ${output}"
)

run_unknown_subcommand_test() (
  set -euo pipefail

  local sandbox
  local output_file
  sandbox="$(setup_sandbox basic-biblatex)"
  trap 'rm -rf "$sandbox"' EXIT
  output_file="$sandbox/logs/unknown-command.log"

  export HOME="$sandbox/home"
  export TEXMFHOME="$sandbox/texmf-home"
  export PATH="$sandbox/bin:$PATH"

  (
    cd "$sandbox/repo"
    assert_command_fails "$output_file" latexctl/bin/latexctl nonsense
  )

  assert_file_contains "$output_file" "Unknown subcommand"
)

run_missing_tex_package_classification_test
run_missing_local_asset_classification_test
run_missing_pathful_local_file_classification_test
run_missing_font_metric_classification_test
run_unicode_character_classification_test
run_build_writes_user_error_report_test
run_build_writes_environment_error_report_test
run_build_writes_markdown_report_test
run_bootstrap_uses_internal_scaffold_test
run_ctan_mirror_uses_env_override_test
run_ctan_mirror_uses_first_configured_mirror_test
run_unknown_subcommand_test

echo "PASS: test_latexctl.sh"
