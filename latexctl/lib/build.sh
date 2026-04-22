#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="build-latex"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${TOOLING_ROOT}/lib/common.sh"
source "${TOOLING_ROOT}/lib/classify.sh"

REPO_ROOT="$(latexctl_repo_root)"
SYNC_SCRIPT="${TOOLING_ROOT}/lib/sync.sh"
LATEXCTL_BIN="${TOOLING_ROOT}/bin/latexctl"
LATEXMK_BIN="${LATEXMK:-latexmk}"
DEFAULT_MAIN_TEX="tex/main.tex"
DEFAULT_LATEXMK_ARGS=(-interaction=nonstopmode -file-line-error)
ERROR_OUTPUT_DIR="${LATEX_ERROR_OUTPUT_DIR:-.latex-errors}"
BUILD_RETRY_INSTALLS_FILE="${LATEX_BUILD_RETRY_INSTALLS_FILE:-.build_retry_installs}"
BUILD_REPORT_FILE="${REPO_ROOT}/build-report.md"

log() {
  echo "[${SCRIPT_NAME}] $*"
}

usage() {
  cat <<'USAGE'
Usage:
  bin/latexctl build [main-tex] [latexmk-arg ...]
  bin/latexctl build --help

Description:
  Run smart sync, compile with latexmk, and retry after bounded missing-file
  installs when the build log exposes a recoverable TeX Live package miss.
USAGE
}

append_unique() {
  local value="$1"
  local existing

  [[ -n "${value}" ]] || return 0

  for existing in "${LOG_CANDIDATE_DIRS[@]}"; do
    if [[ "${existing}" == "${value}" ]]; then
      return 0
    fi
  done

  LOG_CANDIDATE_DIRS+=("${value}")
}

build_search_path() {
  local root="$1"
  local existing="${2:-}"

  if [[ -n "${existing}" ]]; then
    printf '%s//:%s:\n' "${root}" "${existing}"
    return 0
  fi

  printf '%s//:\n' "${root}"
}

clean_auxiliary_outputs() {
  [[ -d "${MAIN_TEX_DIR}" ]] || return 0

  find "${MAIN_TEX_DIR}" -type f \
    \( \
      -name '*.aux' -o \
      -name '*.bbl' -o \
      -name '*.bcf' -o \
      -name '*.blg' -o \
      -name '*.fdb_latexmk' -o \
      -name '*.fls' -o \
      -name '*.lof' -o \
      -name '*.log' -o \
      -name '*.lot' -o \
      -name '*.out' -o \
      -name '*.run.xml' -o \
      -name '*.synctex.gz' -o \
      -name '*.toc' -o \
      -name '*.xdv' -o \
      -name 'missfont.log' \
    \) \
    -delete
}

parse_latexmk_metadata() {
  local arg
  local next_index

  MAIN_TEX_DIR="$(dirname "${MAIN_TEX}")"
  MAIN_TEX_NAME="$(basename "${MAIN_TEX%.tex}")"
  LATEXMK_JOBNAME="${MAIN_TEX_NAME}"
  LATEXMK_OUTDIR=""
  LATEXMK_AUXDIR=""

  for (( next_index=0; next_index<${#EXTRA_LATEXMK_ARGS[@]}; next_index++ )); do
    arg="${EXTRA_LATEXMK_ARGS[$next_index]}"
    case "${arg}" in
      -jobname=*)
        LATEXMK_JOBNAME="${arg#-jobname=}"
        ;;
      -jobname)
        if (( next_index + 1 < ${#EXTRA_LATEXMK_ARGS[@]} )); then
          next_index=$((next_index + 1))
          LATEXMK_JOBNAME="${EXTRA_LATEXMK_ARGS[$next_index]}"
        fi
        ;;
      -outdir=*)
        LATEXMK_OUTDIR="${arg#-outdir=}"
        ;;
      -outdir)
        if (( next_index + 1 < ${#EXTRA_LATEXMK_ARGS[@]} )); then
          next_index=$((next_index + 1))
          LATEXMK_OUTDIR="${EXTRA_LATEXMK_ARGS[$next_index]}"
        fi
        ;;
      -auxdir=*)
        LATEXMK_AUXDIR="${arg#-auxdir=}"
        ;;
      -auxdir)
        if (( next_index + 1 < ${#EXTRA_LATEXMK_ARGS[@]} )); then
          next_index=$((next_index + 1))
          LATEXMK_AUXDIR="${EXTRA_LATEXMK_ARGS[$next_index]}"
        fi
        ;;
    esac
  done

  if [[ -n "${LATEXMK_OUTDIR}" && "${LATEXMK_OUTDIR}" != /* ]]; then
    LATEXMK_OUTDIR="${MAIN_TEX_DIR%/}/${LATEXMK_OUTDIR}"
  fi

  if [[ -n "${LATEXMK_AUXDIR}" && "${LATEXMK_AUXDIR}" != /* ]]; then
    LATEXMK_AUXDIR="${MAIN_TEX_DIR%/}/${LATEXMK_AUXDIR}"
  fi

  if [[ -n "${LATEXMK_OUTDIR}" ]]; then
    OUTPUT_PDF_DIR="${LATEXMK_OUTDIR}"
  else
    OUTPUT_PDF_DIR="${MAIN_TEX_DIR}"
  fi

  OUTPUT_PDF_PATH="${OUTPUT_PDF_DIR%/}/${LATEXMK_JOBNAME}.pdf"
}

archive_existing_pdf() {
  local pdf_path="$1"
  local pdf_dir
  local pdf_name
  local pdf_base
  local archived_pdf

  [[ -f "${pdf_path}" ]] || return 0

  pdf_dir="$(dirname "${pdf_path}")"
  pdf_name="$(basename "${pdf_path}")"
  pdf_base="${pdf_name%.pdf}"
  archived_pdf="${pdf_dir}/${pdf_base}.previous.pdf"

  cp -pf "${pdf_path}" "${archived_pdf}"
}

discover_log_file() {
  local marker_file="$1"
  local candidate_dir
  local candidate_name
  local candidate_path
  local fallback_log
  local -a candidate_names=("${LATEXMK_JOBNAME}.log")

  LOG_CANDIDATE_DIRS=()
  append_unique "${LATEXMK_AUXDIR}"
  append_unique "${LATEXMK_OUTDIR}"
  append_unique "${MAIN_TEX_DIR}"
  append_unique "."

  if [[ "${LATEXMK_JOBNAME}" != "${MAIN_TEX_NAME}" ]]; then
    candidate_names+=("${MAIN_TEX_NAME}.log")
  fi

  for candidate_dir in "${LOG_CANDIDATE_DIRS[@]}"; do
    for candidate_name in "${candidate_names[@]}"; do
      candidate_path="${candidate_dir%/}/${candidate_name}"
      if [[ -f "${candidate_path}" && "${candidate_path}" -nt "${marker_file}" ]]; then
        printf '%s\n' "${candidate_path}"
        return 0
      fi
    done
  done

  fallback_log="$(find . -type f -newer "${marker_file}" \( -name "${LATEXMK_JOBNAME}.log" -o -name "${MAIN_TEX_NAME}.log" \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print }')"
  if [[ -n "${fallback_log}" ]]; then
    printf '%s\n' "${fallback_log}"
    return 0
  fi

  return 1
}

run_latexmk() {
  local -a latexmk_args=()
  local search_root
  local texinputs
  local bibinputs
  local bstinputs

  if [[ ${#EXTRA_LATEXMK_ARGS[@]} -gt 0 ]]; then
    latexmk_args=("${EXTRA_LATEXMK_ARGS[@]}")
  else
    latexmk_args=("${DEFAULT_LATEXMK_ARGS[@]}")
  fi

  if [[ "${FORCE_LATEXMK_RERUN:-0}" == "1" ]]; then
    latexmk_args=(-g "${latexmk_args[@]}")
  fi

  search_root="$(cd "${MAIN_TEX_DIR}" && pwd)"
  texinputs="$(build_search_path "${search_root}" "${TEXINPUTS:-}")"
  bibinputs="$(build_search_path "${search_root}" "${BIBINPUTS:-}")"
  bstinputs="$(build_search_path "${search_root}" "${BSTINPUTS:-}")"

  TEXINPUTS="${texinputs}" \
  BIBINPUTS="${bibinputs}" \
  BSTINPUTS="${bstinputs}" \
    "${LATEXMK_BIN}" -cd -pdf "${latexmk_args[@]}" "${MAIN_TEX}"
}

report_failure_with_classification() {
  local log_file="$1"
  local fallback_message="$2"
  local summary_file
  local scope
  local kind
  local report_file

  if [[ -f "${LATEXCTL_BIN}" && -f "${log_file}" ]]; then
    if "${LATEXCTL_BIN}" classify-error --log "${log_file}" --output-dir "${ERROR_OUTPUT_DIR}" >/dev/null 2>&1; then
      summary_file="${ERROR_OUTPUT_DIR}/summary.env"
      if [[ -f "${summary_file}" ]]; then
        scope="$(awk -F= '$1 == "scope" { print substr($0, 7) }' "${summary_file}")"
        kind="$(awk -F= '$1 == "kind" { print substr($0, 6) }' "${summary_file}")"
        case "${scope}" in
          user)
            report_file="${ERROR_OUTPUT_DIR}/user-errors.log"
            ;;
          *)
            report_file="${ERROR_OUTPUT_DIR}/environment-errors.log"
            ;;
        esac

        log "Error: ${fallback_message} [${scope}/${kind}]." >&2
        log "See ${report_file} and ${summary_file} for a reduced diagnosis." >&2
        return 0
      fi
    fi
  fi

  log "Error: ${fallback_message}" >&2
  return 0
}

write_build_report() {
  local status="$1"
  local log_file="$2"
  local scope="${3:-}"
  local kind="${4:-}"
  local artifact="${5:-unknown}"
  local details="${6:-}"

  latexctl_report_build \
    --status "${status}" \
    --log "${log_file}" \
    --output "${BUILD_REPORT_FILE}" \
    --output-dir "${ERROR_OUTPUT_DIR}" \
    --scope "${scope}" \
    --kind "${kind}" \
    --artifact "${artifact}" \
    --details "${details}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 ]]; then
  MAIN_TEX="${DEFAULT_MAIN_TEX}"
  EXTRA_LATEXMK_ARGS=()
elif [[ "${1}" == -* ]]; then
  MAIN_TEX="${DEFAULT_MAIN_TEX}"
  EXTRA_LATEXMK_ARGS=("$@")
else
  MAIN_TEX="$1"
  shift
  EXTRA_LATEXMK_ARGS=("$@")
fi

LOG_FILE="${MAIN_TEX%.tex}.log"
parse_latexmk_metadata
archive_existing_pdf "${OUTPUT_PDF_PATH}"
clean_auxiliary_outputs

"${SYNC_SCRIPT}"

attempt=1
FORCE_LATEXMK_RERUN=0
declare -A ATTEMPTED_ASSETS=()

while true; do
  attempt_marker="$(mktemp "${TMPDIR:-/tmp}/build-latex-attempt.XXXXXX")"
  if run_latexmk; then
    active_log_file="$(discover_log_file "${attempt_marker}" || true)"
    rm -f "${attempt_marker}"
    if [[ -n "${active_log_file}" ]]; then
      write_build_report "success" "${active_log_file}"
    else
      write_build_report "success" "${MAIN_TEX_DIR%/}/${LATEXMK_JOBNAME}.log"
    fi
    exit 0
  fi

  active_log_file="$(discover_log_file "${attempt_marker}" || true)"
  rm -f "${attempt_marker}"
  if [[ -z "${active_log_file}" ]]; then
    log "Error: build failed without a discoverable log file for retry analysis." >&2
    exit 1
  fi

  class_output="$(latexctl_classify_log "${active_log_file}" || true)"
  scope="$(echo "${class_output}" | awk -F= '$1 == "scope" { print substr($0, 7) }')"
  kind="$(echo "${class_output}" | awk -F= '$1 == "kind" { print substr($0, 6) }')"
  missing_file="$(echo "${class_output}" | awk -F= '$1 == "artifact" { print substr($0, 10) }')"
  details="$(echo "${class_output}" | awk -F= '$1 == "details" { print substr($0, 9) }')"

  if [[ "${scope}" == "environment" && ( "${kind}" == "missing_tex_asset" || "${kind}" == "missing_font_metric" ) && -n "${missing_file}" && "${missing_file}" != "unknown" ]]; then
    if [[ -n "${ATTEMPTED_ASSETS[${missing_file}]:-}" ]]; then
      report_failure_with_classification "${active_log_file}" "build failed with persistent missing environment asset: ${missing_file}"
      write_build_report "failure" "${active_log_file}" "${scope}" "${kind}" "${missing_file}" "${details}"
      exit 1
    fi

    log "Detected missing environment asset ${missing_file}; resolving owner and retrying."
    ATTEMPTED_ASSETS["${missing_file}"]=1
    LATEXCTL_BUILD_RETRY_INSTALLS_FILE="${BUILD_RETRY_INSTALLS_FILE}" "${SYNC_SCRIPT}" --resolve-file "${missing_file}"
    FORCE_LATEXMK_RERUN=1
    attempt=$((attempt + 1))
  elif [[ "${scope}" == "user" && "${kind}" == "missing_local_"* ]]; then
    report_failure_with_classification "${active_log_file}" "build failed due to local-project missing file ${missing_file}"
    write_build_report "failure" "${active_log_file}" "${scope}" "${kind}" "${missing_file}" "${details}"
    exit 1
  else
    report_failure_with_classification "${active_log_file}" "build failed without a recoverable missing-file entry in ${active_log_file}"
    write_build_report "failure" "${active_log_file}" "${scope}" "${kind}" "${missing_file}" "${details}"
    exit 1
  fi
done

log "Error: retry limit exceeded."
exit 1
