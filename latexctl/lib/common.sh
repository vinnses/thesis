#!/usr/bin/env bash

latexctl_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

latexctl_log() {
  echo "[latexctl] $*"
}

latexctl_local_project_file_exists() {
  local candidate="$1"
  local repo_root
  local tex_dir
  local candidate_path

  repo_root="$(latexctl_repo_root)"
  tex_dir="${repo_root}/tex"

  [[ -n "${candidate}" ]] || return 1

  if [[ "${candidate}" == */* ]]; then
    candidate_path="${tex_dir}/${candidate}"
    [[ -f "${candidate_path}" ]] && return 0
  fi

  find "${tex_dir}" -type f -name "${candidate##*/}" -print -quit | grep -q .
}

latexctl_summary_value() {
  local file="$1"
  local key="$2"

  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2) }' "${file}"
}

latexctl_extract_warning_blocks() {
  local log_file="$1"

  awk '
    function flush_block() {
      if (block != "") {
        sub(/\n+$/, "", block)
        if (printed) {
          printf "\n"
        }
        printf "%s\n", block
        block = ""
        printed = 1
      }
    }

    function is_warning_start(line) {
      return line ~ /Warning:/
    }

    function is_warning_continuation(line) {
      return line ~ /^[[:space:]]+/ || line ~ /^\([^)]*\)/
    }

    {
      line = $0

      if (in_block) {
        if (is_warning_start(line)) {
          flush_block()
          block = line "\n"
          next
        }

        if (is_warning_continuation(line)) {
          block = block line "\n"
          next
        }

        flush_block()
        in_block = 0
      }

      if (is_warning_start(line)) {
        block = line "\n"
        in_block = 1
      }
    }

    END {
      flush_block()
    }
  ' "${log_file}" 2>/dev/null || true
}

latexctl_extract_fatal_blocks() {
  local log_file="$1"

  awk '
    function flush_block() {
      if (block != "") {
        sub(/\n+$/, "", block)
        if (printed) {
          printf "\n"
        }
        printf "%s\n", block
        block = ""
        printed = 1
      }
    }

    function is_error_start(line) {
      return line ~ /^! / || line ~ /LaTeX Error:/ || line ~ /Undefined control sequence/ || line ~ /Unicode character/
    }

    function is_error_continuation(line) {
      return line ~ /^[[:space:]]+/ || line ~ /^l\.[0-9]+/ || line ~ /^<[^>]+>/ || line ~ /^Type / || line ~ /^See the /
    }

    {
      line = $0

      if (in_block) {
        if (is_error_start(line)) {
          flush_block()
          block = line "\n"
          next
        }

        if (is_error_continuation(line)) {
          block = block line "\n"
          next
        }

        flush_block()
        in_block = 0
      }

      if (is_error_start(line)) {
        block = line "\n"
        in_block = 1
      }
    }

    END {
      flush_block()
    }
  ' "${log_file}" 2>/dev/null || true
}

latexctl_count_blocks() {
  awk '
    BEGIN { count = 0; in_block = 0 }
    NF {
      if (!in_block) {
        count++
        in_block = 1
      }
      next
    }
    {
      in_block = 0
    }
    END {
      printf "%d\n", count
    }
  '
}

latexctl_write_optional_text_file() {
  local output_file="$1"
  local content="$2"

  if [[ -n "${content}" ]]; then
    mkdir -p "$(dirname "${output_file}")"
    printf '%s\n' "${content}" > "${output_file}"
    return 0
  fi

  rm -f "${output_file}"
}

latexctl_write_markdown_report() {
  local report_file="$1"
  local status="$2"
  local log_file="$3"
  local scope="$4"
  local kind="$5"
  local artifact="$6"
  local details="$7"
  local error_count="$8"
  local warning_count="$9"
  local error_details_file="${10}"
  local warning_details_file="${11}"
  local report_dir

  report_dir="$(dirname "${report_file}")"
  mkdir -p "${report_dir}"

  {
    printf '# LaTeX Build Report\n\n'
    printf -- '- Status: `%s`\n' "${status}"
    printf -- '- Log file: `%s`\n' "${log_file}"

    if [[ -n "${scope}" && -n "${kind}" ]]; then
      printf -- '- Classification: `%s/%s`\n' "${scope}" "${kind}"
    fi

    if [[ -n "${artifact}" && "${artifact}" != "unknown" ]]; then
      printf -- '- Artifact: `%s`\n' "${artifact}"
    fi

    if [[ -n "${details}" ]]; then
      printf -- '- Details: %s\n' "${details}"
    fi

    printf -- '- Error count: `%s`\n' "${error_count}"
    if [[ -n "${error_details_file}" ]]; then
      printf -- '- Error details: `%s`\n' "${error_details_file}"
    fi

    printf -- '- Warning count: `%s`\n' "${warning_count}"
    if [[ -n "${warning_details_file}" ]]; then
      printf -- '- Warning details: `%s`\n' "${warning_details_file}"
    fi
  } > "${report_file}"
}

latexctl_report_build() {
  local status=""
  local log_file=""
  local output_file=""
  local output_dir=""
  local scope=""
  local kind=""
  local artifact="unknown"
  local details=""
  local class_output=""
  local fatal_excerpt=""
  local warning_excerpt=""
  local error_count="0"
  local warning_count="0"
  local error_details_file=""
  local warning_details_file=""
  local key=""
  local value=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --status)
        status="${2:-}"
        shift 2
        ;;
      --log)
        log_file="${2:-}"
        shift 2
        ;;
      --output)
        output_file="${2:-}"
        shift 2
        ;;
      --output-dir)
        output_dir="${2:-}"
        shift 2
        ;;
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      --kind)
        kind="${2:-}"
        shift 2
        ;;
      --artifact)
        artifact="${2:-unknown}"
        shift 2
        ;;
      --details)
        details="${2:-}"
        shift 2
        ;;
      --help|-h)
        cat <<'USAGE'
Usage:
  bin/latexctl report-build --status <success|failure> --log <path> --output <file> [--output-dir <dir>]
USAGE
        return 0
        ;;
      *)
        echo "Unknown report-build argument: ${1}" >&2
        return 2
        ;;
    esac
  done

  if [[ -z "${status}" || -z "${output_file}" ]]; then
    echo "report-build requires --status and --output." >&2
    return 2
  fi

  if [[ -z "${log_file}" ]]; then
    log_file="unknown"
  fi

  if [[ -f "${log_file}" ]]; then
    if [[ -z "${scope}" && -z "${kind}" && "${status}" == "failure" ]]; then
      class_output="$(latexctl_classify_log "${log_file}" || true)"
      while IFS='=' read -r key value; do
        case "${key}" in
          scope)
            scope="${value}"
            ;;
          kind)
            kind="${value}"
            ;;
          artifact)
            artifact="${value}"
            ;;
          details)
            details="${value}"
            ;;
        esac
      done < <(printf '%s\n' "${class_output}")
    fi

    fatal_excerpt="$(latexctl_extract_fatal_blocks "${log_file}" || true)"
    warning_excerpt="$(latexctl_extract_warning_blocks "${log_file}" || true)"
    error_count="$(printf '%s' "${fatal_excerpt}" | latexctl_count_blocks)"
    warning_count="$(printf '%s' "${warning_excerpt}" | latexctl_count_blocks)"
  fi

  if [[ -n "${output_dir}" ]]; then
    error_details_file="${output_dir}/errors.log"
    warning_details_file="${output_dir}/warnings.log"
    latexctl_write_optional_text_file "${error_details_file}" "${fatal_excerpt}"
    latexctl_write_optional_text_file "${warning_details_file}" "${warning_excerpt}"

    if [[ ! -f "${error_details_file}" ]]; then
      error_details_file=""
    fi

    if [[ ! -f "${warning_details_file}" ]]; then
      warning_details_file=""
    fi
  fi

  if [[ -n "${output_dir}" && "${status}" == "failure" && -f "${log_file}" ]]; then
    if [[ -z "${scope}" || -z "${kind}" ]]; then
      class_output="$(latexctl_classify_log "${log_file}" || true)"
      while IFS='=' read -r key value; do
        case "${key}" in
          scope)
            scope="${value}"
            ;;
          kind)
            kind="${value}"
            ;;
          artifact)
            artifact="${value}"
            ;;
          details)
            details="${value}"
            ;;
        esac
      done < <(printf '%s\n' "${class_output}")
    fi
    latexctl_write_scope_logs "${output_dir}" "${scope}" "${kind}" "${artifact}" "${log_file}" "${details}"
  fi

  latexctl_write_markdown_report \
    "${output_file}" \
    "${status}" \
    "${log_file}" \
    "${scope}" \
    "${kind}" \
    "${artifact}" \
    "${details}" \
    "${error_count}" \
    "${warning_count}" \
    "${error_details_file}" \
    "${warning_details_file}"
}

latexctl_write_scope_logs() {
  local output_dir="$1"
  local scope="$2"
  local kind="$3"
  local artifact="$4"
  local source_log="$5"
  local details="$6"
  local summary_file="${output_dir}/summary.env"
  local target_file

  mkdir -p "${output_dir}"
  : > "${output_dir}/user-errors.log"
  : > "${output_dir}/environment-errors.log"

  case "${scope}" in
    user)
      target_file="${output_dir}/user-errors.log"
      ;;
    environment)
      target_file="${output_dir}/environment-errors.log"
      ;;
    *)
      target_file="${output_dir}/environment-errors.log"
      ;;
  esac

  cat > "${summary_file}" <<EOF
scope=${scope}
kind=${kind}
artifact=${artifact}
source_log=${source_log}
EOF

  cat > "${target_file}" <<EOF
scope=${scope}
kind=${kind}
artifact=${artifact}
source_log=${source_log}
details=${details}
EOF
}
