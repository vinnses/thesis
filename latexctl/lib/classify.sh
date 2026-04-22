#!/usr/bin/env bash

latexctl_extract_missing_file() {
  local log_file="$1"

  perl -ne '
    if (/File `([^'\''[:space:]]+)'\'' not found\./) {
      $candidate = $1;
    }
    END {
      print $candidate if defined $candidate;
    }
  ' "${log_file}"
}

latexctl_extract_missing_font_metric() {
  local log_file="$1"
  local artifact

  artifact="$(sed -n 's/.*mktextfm \([^[:space:]]\+\).*/\1/p' "${log_file}" | tail -n 1)"
  if [[ -n "${artifact}" ]]; then
    printf '%s\n' "${artifact}"
    return 0
  fi

  artifact="$(sed -n 's/.*=\([^ =][^ ]*\) at .*/\1/p' "${log_file}" | tail -n 1)"
  if [[ -n "${artifact}" ]]; then
    printf '%s\n' "${artifact}"
    return 0
  fi

  return 1
}

latexctl_extract_missing_tool() {
  local log_file="$1"

  perl -ne '
    if (/^sh: ([^:[:space:]]+): command not found/) {
      $tool = $1;
    }
    elsif (/^([^:[:space:]]+): command not found/) {
      $tool = $1;
    }
    END {
      print $tool if defined $tool;
    }
  ' "${log_file}"
}

latexctl_extract_unicode_character_error() {
  local log_file="$1"

  perl -ne '
    if (/Unicode character .* \((U\+[0-9A-F]+)\)/) {
      print "$1\n";
      exit 0;
    }
  ' "${log_file}"
}

latexctl_is_tex_environment_artifact() {
  local candidate="$1"

  case "${candidate}" in
    *.sty|*.cls|*.def|*.ldf|*.tex|*.fd|*.enc|*.map|*.tfm|*.vf|*.pfb|*.otf|*.ttf)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

latexctl_classify_log() {
  local log_file="$1"
  local scope="environment"
  local kind="non_recoverable"
  local artifact="unknown"
  local details="Could not classify the LaTeX failure."
  local missing_font_metric=""
  local missing_tool=""
  local unicode_error=""
  local missing_file=""

  missing_font_metric="$(latexctl_extract_missing_font_metric "${log_file}" || true)"
  if [[ -n "${missing_font_metric}" ]]; then
    scope="environment"
    kind="missing_font_metric"
    artifact="${missing_font_metric}"
    details="TeX runtime requested a font metric that is not available in the environment."
    printf 'scope=%s\nkind=%s\nartifact=%s\ndetails=%s\n' "${scope}" "${kind}" "${artifact}" "${details}"
    return 0
  fi

  missing_tool="$(latexctl_extract_missing_tool "${log_file}" || true)"
  if [[ -n "${missing_tool}" ]]; then
    scope="environment"
    kind="missing_tool"
    artifact="${missing_tool}"
    details="The build depends on an external tool that is not available in PATH."
    printf 'scope=%s\nkind=%s\nartifact=%s\ndetails=%s\n' "${scope}" "${kind}" "${artifact}" "${details}"
    return 0
  fi

  unicode_error="$(latexctl_extract_unicode_character_error "${log_file}" || true)"
  if [[ -n "${unicode_error}" ]]; then
    scope="user"
    kind="unicode_character"
    artifact="${unicode_error}"
    details="The document or an auxiliary file contains a Unicode character that this LaTeX path cannot process."
    printf 'scope=%s\nkind=%s\nartifact=%s\ndetails=%s\n' "${scope}" "${kind}" "${artifact}" "${details}"
    return 0
  fi

  missing_file="$(latexctl_extract_missing_file "${log_file}" || true)"
  if [[ -n "${missing_file}" ]]; then
    if latexctl_is_tex_environment_artifact "${missing_file}"; then
      if [[ "${missing_file}" == */* ]] || latexctl_local_project_file_exists "${missing_file}"; then
        scope="user"
        kind="missing_local_input"
        details="The document references a TeX input that the local project does not provide."
      else
        scope="environment"
        kind="missing_tex_asset"
        details="A TeX runtime asset is missing from the environment."
      fi
    else
      scope="user"
      kind="missing_local_asset"
      details="The document references a local asset that is missing from the project."
    fi

    artifact="${missing_file}"
    printf 'scope=%s\nkind=%s\nartifact=%s\ndetails=%s\n' "${scope}" "${kind}" "${artifact}" "${details}"
    return 0
  fi

  if grep -F "gave an error in previous invocation of latexmk" "${log_file}" >/dev/null 2>&1; then
    scope="environment"
    kind="stale_build_state"
    artifact="latexmk"
    details="Latexmk is reporting a previous failed invocation and stale build state."
  fi

  printf 'scope=%s\nkind=%s\nartifact=%s\ndetails=%s\n' "${scope}" "${kind}" "${artifact}" "${details}"
}

latexctl_classify_error() {
  local log_file=""
  local output_dir=""
  local key=""
  local value=""
  local scope=""
  local kind=""
  local artifact=""
  local details=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --log)
        log_file="${2:-}"
        shift 2
        ;;
      --output-dir)
        output_dir="${2:-}"
        shift 2
        ;;
      --help|-h)
        cat <<'USAGE'
Usage:
  bin/latexctl classify-error --log <path> --output-dir <dir>
USAGE
        return 0
        ;;
      *)
        echo "Unknown classify-error argument: ${1}" >&2
        return 2
        ;;
    esac
  done

  if [[ -z "${log_file}" || -z "${output_dir}" ]]; then
    echo "classify-error requires --log and --output-dir." >&2
    return 2
  fi

  if [[ ! -f "${log_file}" ]]; then
    echo "Missing log file: ${log_file}" >&2
    return 1
  fi

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
  done < <(latexctl_classify_log "${log_file}")

  latexctl_write_scope_logs "${output_dir}" "${scope}" "${kind}" "${artifact}" "${log_file}" "${details}"
}
