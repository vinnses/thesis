#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="ziptex"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEX_DIR="${REPO_ROOT}/tex"

log() {
  echo "[${SCRIPT_NAME}] $*"
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/ziptex.sh [project_name]
  scripts/ziptex.sh --help

Description:
  Create a zip archive for external platforms (e.g., Overleaf) containing only
  source files from tex/.

Behavior:
  - Output archive is created in repository root
  - Default output name: export.zip
  - If [project_name] is provided, output name: <project_name>.zip
  - Excludes runtime directories, VCS metadata, and LaTeX build artifacts

Exit Codes:
  0  Success
  1  Runtime error
  2  Invalid usage
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  log "Error: expected at most one optional argument [project_name]." >&2
  usage >&2
  exit 2
fi

if ! command -v zip >/dev/null 2>&1; then
  log "Error: zip command is not available." >&2
  exit 1
fi

if [[ ! -d "${TEX_DIR}" ]]; then
  log "Error: missing tex directory: ${TEX_DIR}" >&2
  exit 1
fi

archive_name="export.zip"
if [[ $# -eq 1 ]]; then
  archive_name="${1}.zip"
fi
archive_path="${REPO_ROOT}/${archive_name}"

if [[ -f "${archive_path}" ]]; then
  log "Destructive action: removing existing archive ${archive_name}"
  rm -f "${archive_path}"
fi

mapfile -t export_files < <(
  cd "${TEX_DIR}" &&
  find . -type f \
    ! -path './.git/*' \
    ! -path './.texmf/*' \
    ! -path './.texlive/*' \
    ! -path './latex.out/*' \
    ! -name '*.aux' \
    ! -name '*.bbl' \
    ! -name '*.bcf' \
    ! -name '*.blg' \
    ! -name '*.fdb_latexmk' \
    ! -name '*.fls' \
    ! -name '*.lof' \
    ! -name '*.lot' \
    ! -name '*.out' \
    ! -name '*.run.xml' \
    ! -name '*.synctex.gz' \
    ! -name '*.toc' \
    ! -name '*.xdv' \
    ! -name '*.log' \
    ! -name '*.pdf' | LC_ALL=C sort
)

if [[ ${#export_files[@]} -eq 0 ]]; then
  log "Error: no exportable source files found under tex/." >&2
  exit 1
fi

(
  cd "${TEX_DIR}"
  zip -q "${archive_path}" "${export_files[@]}"
)

log "Created archive: ${archive_path}"
