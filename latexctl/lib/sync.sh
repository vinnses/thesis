#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sync-tlmgr"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${TOOLING_ROOT}/lib/common.sh"

REPO_ROOT="$(latexctl_repo_root)"
TEX_DIR="${REPO_ROOT}/tex"
PACKAGE_FILE="${REPO_ROOT}/.used_packages"
TOOL_FILE="${REPO_ROOT}/.used_tools"
PACKAGE_OVERRIDE_FILE="${REPO_ROOT}/latexctl/package-overrides.conf"
TOOLS_OVERRIDE_FILE="${REPO_ROOT}/extra-tools.txt"
declare -a LAST_INSTALLED_USER_PACKAGES=()

log() {
  echo "[${SCRIPT_NAME}] $*"
}

append_build_retry_install_records() {
  local artifact="$1"
  local package
  local timestamp
  local record_file="${LATEXCTL_BUILD_RETRY_INSTALLS_FILE:-}"

  [[ -n "${record_file}" ]] || return 0
  [[ ${#LAST_INSTALLED_USER_PACKAGES[@]} -gt 0 ]] || return 0

  mkdir -p "$(dirname "${record_file}")"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  for package in "${LAST_INSTALLED_USER_PACKAGES[@]}"; do
    printf '%s artifact=%s package=%s\n' "${timestamp}" "${artifact}" "${package}" >> "${record_file}"
  done
}

usage() {
  cat <<'USAGE'
Usage:
  bin/latexctl sync
  bin/latexctl sync --resolve-file <missing-file>
  bin/latexctl sync --help

Description:
  Scan tex/ sources for LaTeX package dependencies and install any missing
  tlmgr packages, or resolve and install the owner of a single missing file.

Behavior:
  - Scans .tex/.cls/.sty in tex/
  - Parses \usepackage{...} and \RequirePackage{...}
  - Detects biblatex backend=biber and includes biber as a system tool when needed
  - Ignores comments (%), supports inline comments and comma lists
  - Writes sorted unique package list to .used_packages
  - Writes sorted unique non-relocatable tools list to .used_tools
  - Initializes tlmgr user tree automatically when needed
  - Installs missing user packages with tlmgr --usermode
  - Installs missing non-relocatable tools with sudo tlmgr install
  - Resolves missing-file owners with --resolve-file <missing-file>
USAGE
}

MODE="scan"
RESOLVE_FILE_NAME=""

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --resolve-file)
    MODE="resolve-file"
    RESOLVE_FILE_NAME="${2:-}"
    if [[ -z "${RESOLVE_FILE_NAME}" || $# -ne 2 ]]; then
      log "Error: --resolve-file requires exactly one file argument." >&2
      usage >&2
      exit 2
    fi
    ;;
  "")
    ;;
  *)
    log "Error: this command does not accept positional arguments." >&2
    usage >&2
    exit 2
    ;;
esac

mkdir -p "${TEX_DIR}"

mapfile -t source_files < <(find "${TEX_DIR}" -type f \( -name '*.tex' -o -name '*.cls' -o -name '*.sty' \) | LC_ALL=C sort)

if ! command -v tlmgr >/dev/null 2>&1; then
  log "Error: tlmgr is not available in PATH." >&2
  exit 1
fi

scan_tex_modules() {
  perl -0777 -ne '
    s/(?<!\\)%.*$//mg;

    while (/\\documentclass\s*(?:\[[^\]]*\]\s*)?\{([^}]*)\}/sg) {
      my $list = $1;
      for my $cls (split /,/, $list) {
        $cls =~ s/^\s+|\s+$//g;
        next if $cls eq q{};
        print "class:$cls\n";
      }
    }

    while (/\\(?:usepackage|RequirePackage)\s*(?:\[[^\]]*\]\s*)?\{([^}]*)\}/sg) {
      my $list = $1;
      for my $pkg (split /,/, $list) {
        $pkg =~ s/^\s+|\s+$//g;
        next if $pkg eq q{};
        print "package:$pkg\n";
      }
    }
  ' "${source_files[@]}" | LC_ALL=C sort -u
}

strip_comments_and_trim() {
  local line="$1"

  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  printf '%s\n' "${line}"
}

module_filename() {
  local kind="$1"
  local name="$2"

  case "$kind" in
    class)
      printf '%s.cls\n' "$name"
      ;;
    package)
      printf '%s.sty\n' "$name"
      ;;
    *)
      return 1
      ;;
  esac
}

logical_name_from_filename() {
  local filename="$1"
  local logical_name="${filename##*/}"

  logical_name="${logical_name%.*}"
  printf '%s\n' "${logical_name}"
}

tlmgr_package_exists() {
  local package_name="$1"

  tlmgr info "$package_name" 2>/dev/null | awk '
    /^package:/ { seen=1 }
    /^category:/ && $2 == "Package" { category_ok=1 }
    END { exit !(seen && category_ok) }
  '
}

lookup_package_override() {
  local kind="$1"
  local logical_name="$2"
  local filename="$3"
  local key
  local value

  [[ -f "${PACKAGE_OVERRIDE_FILE}" ]] || return 1

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(strip_comments_and_trim "${line}")"
    [[ -n "${line}" ]] || continue
    [[ "${line}" == *"="* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    case "${key}" in
      "${filename}"|"${kind}:${logical_name}"|"${logical_name}")
        [[ -n "${value}" ]] || return 1
        printf '%s\n' "${value}"
        return 0
        ;;
    esac
  done < "${PACKAGE_OVERRIDE_FILE}"

  return 1
}

infer_required_tools() {
  local inferred_tools=()
  local override_tools=()
  local line

  if [[ ${#source_files[@]} -gt 0 ]]; then
    if perl -0777 -ne '
      s/(?<!\\)%.*$//mg;
      if (/\\usepackage\s*\[([^\]]*)\]\s*\{biblatex\}/sg) {
        my $opts = $1;
        if ($opts =~ /(?:^|,)\s*backend\s*=\s*biber\s*(?:,|$)/) {
          exit 0;
        }
      }
      exit 1;
    ' "${source_files[@]}"; then
      inferred_tools+=("biber")
    fi
  fi

  if [[ -f "${TOOLS_OVERRIDE_FILE}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="$(strip_comments_and_trim "${line}")"
      [[ -n "${line}" ]] || continue
      override_tools+=("${line}")
    done < "${TOOLS_OVERRIDE_FILE}"
  fi

  if [[ ${#inferred_tools[@]} -eq 0 && ${#override_tools[@]} -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${inferred_tools[@]}" "${override_tools[@]}" | LC_ALL=C sort -u
}

collect_search_hits() {
  local search_pattern="$1"

  tlmgr search --global --file "${search_pattern}" 2>/dev/null \
    | awk -F: '
        /:$/ {
          package = $1
          next
        }
        /^[[:space:]]+/ {
          path = $0
          sub(/^[[:space:]]+/, "", path)
          if (package ~ /^(collection-|scheme-|texlive-|00texlive|hyphen-)/) {
            next
          }
          if (package ~ /-doc$/) {
            next
          }
          if (package ~ /-src$/) {
            next
          }
          printf "%s\t%s\n", package, path
        }
      ' \
    | LC_ALL=C sort -u
}

filter_search_hits_by_basename() {
  local match_mode="$1"
  local filename="$2"

  awk -F'\t' -v match_mode="${match_mode}" -v filename="${filename}" '
    function basename(path) {
      sub(/^.*\//, "", path)
      return path
    }

    {
      path = $2
      file = basename(path)
      if (match_mode == "exact" && file == filename) {
        print $0
        next
      }
      if (match_mode == "with-extension" && index(file, filename ".") == 1) {
        print $0
      }
    }
  '
}

pick_preferred_candidate() {
  local filename="$1"
  shift
  local hits=("$@")
  local hit
  local package
  local path
  local extension
  local score
  local best_score=-1
  local best_package=""
  local best_count=0

  [[ ${#hits[@]} -gt 0 ]] || return 1

  for hit in "${hits[@]}"; do
    package="${hit%%$'\t'*}"
    path="${hit#*$'\t'}"
    extension="${path##*.}"
    score=0

    if [[ "${path##*/}" == "${filename}" ]]; then
      score=$((score + 100))
    fi

    if [[ "${filename}" != *.* ]]; then
      case "${extension}" in
        tfm)
          score=$((score + 80))
          ;;
        vf|enc|map|pfb|otf|ttf)
          score=$((score + 60))
          ;;
        htf)
          score=$((score + 10))
          ;;
      esac
    fi

    case "${path}" in
      */fonts/*)
        score=$((score + 20))
        ;;
      */tex4ht/*)
        score=$((score - 20))
        ;;
    esac

    if (( score > best_score )); then
      best_score=${score}
      best_package="${package}"
      best_count=1
    elif (( score == best_score )); then
      if [[ "${package}" != "${best_package}" ]]; then
        best_count=$((best_count + 1))
      fi
    fi
  done

  if (( best_count == 1 )) && [[ -n "${best_package}" ]]; then
    printf '%s\n' "${best_package}"
    return 0
  fi

  return 1
}

resolve_package_owner() {
  local kind="$1"
  local logical_name="$2"
  local filename="$3"
  local override_package
  local candidates=()
  local search_hits=()
  local preferred_package

  if override_package="$(lookup_package_override "${kind}" "${logical_name}" "${filename}")"; then
    printf '%s\n' "${override_package}"
    return 0
  fi

  if tlmgr_package_exists "$logical_name"; then
    printf '%s\n' "$logical_name"
    return 0
  fi

  mapfile -t search_hits < <(collect_search_hits "/${filename}")
  if [[ ${#search_hits[@]} -gt 0 ]]; then
    mapfile -t search_hits < <(printf '%s\n' "${search_hits[@]}" | filter_search_hits_by_basename exact "${filename}")
  fi

  if [[ ${#search_hits[@]} -gt 0 ]]; then
    mapfile -t candidates < <(printf '%s\n' "${search_hits[@]}" | awk -F'\t' '{ print $1 }' | LC_ALL=C sort -u)
  fi

  # If not found, try searching with a wildcard extension (useful for font metrics)
  if [[ ${#candidates[@]} -eq 0 && "${filename}" != *.* ]]; then
      mapfile -t search_hits < <(collect_search_hits "/${filename}\\..*")
      if [[ ${#search_hits[@]} -gt 0 ]]; then
        mapfile -t search_hits < <(printf '%s\n' "${search_hits[@]}" | filter_search_hits_by_basename with-extension "${filename}")
      fi
      if [[ ${#search_hits[@]} -gt 0 ]]; then
        mapfile -t candidates < <(printf '%s\n' "${search_hits[@]}" | awk -F'\t' '{ print $1 }' | LC_ALL=C sort -u)
      fi
  fi

  if [[ ${#candidates[@]} -eq 1 ]]; then
    printf '%s\n' "${candidates[0]}"
    return 0
  fi

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  if preferred_package="$(pick_preferred_candidate "${filename}" "${search_hits[@]}")"; then
    printf '%s\n' "${preferred_package}"
    return 0
  fi

  log "Error: ambiguous package owner for ${filename}: ${candidates[*]}. Add a mapping to ${PACKAGE_OVERRIDE_FILE} to disambiguate this module." >&2
  return 1
}

install_user_packages() {
  local packages=("$@")
  local pkg
  local missing_packages=()
  local unresolved_packages=()

  LAST_INSTALLED_USER_PACKAGES=()

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ ! -f "${TEXMFHOME:-$HOME/texmf}/tlpkg/texlive.tlpdb" ]]; then
    log "Initializing tlmgr user tree..."
    tlmgr init-usertree
  fi

  mapfile -t installed_packages < <(tlmgr info --only-installed 2>/dev/null | awk '/^package:/{print $2}' | LC_ALL=C sort -u)

  declare -A installed_map=()
  for pkg in "${installed_packages[@]}"; do
    installed_map["$pkg"]=1
  done

  for pkg in "${packages[@]}"; do
    if [[ -z "${installed_map[$pkg]:-}" ]]; then
      missing_packages+=("$pkg")
    fi
  done

  if [[ ${#missing_packages[@]} -eq 0 ]]; then
    log "All required packages are already installed."
    return 0
  fi

  log "Installing missing packages: ${missing_packages[*]}"
  if ! tlmgr --usermode install "${missing_packages[@]}"; then
    mapfile -t installed_after < <(tlmgr info --only-installed 2>/dev/null | awk '/^package:/{print $2}' | LC_ALL=C sort -u)
    declare -A installed_after_map=()
    for pkg in "${installed_after[@]}"; do
      installed_after_map["$pkg"]=1
    done

    for pkg in "${missing_packages[@]}"; do
      if [[ -z "${installed_after_map[$pkg]:-}" ]]; then
        unresolved_packages+=("$pkg")
      fi
    done

    if [[ ${#unresolved_packages[@]} -eq 0 ]]; then
      LAST_INSTALLED_USER_PACKAGES=("${missing_packages[@]}")
      log "tlmgr returned a non-zero status, but all requested packages are now installed."
      return 0
    fi

    log "Error: failed to install one or more packages:" >&2
    printf '  - %s\n' "${unresolved_packages[@]}" >&2
    return 1
  fi

  LAST_INSTALLED_USER_PACKAGES=("${missing_packages[@]}")
  log "Successfully installed missing packages."
}

if [[ "${MODE}" == "resolve-file" ]]; then
  resolve_target="${RESOLVE_FILE_NAME}"
  if latexctl_local_project_file_exists "${resolve_target}"; then
    log "Error: ${resolve_target} is provided by the local project; not resolving it through TeX Live." >&2
    exit 1
  fi

  logical_name="$(logical_name_from_filename "${resolve_target}")"
  if owner="$(resolve_package_owner "file" "${logical_name}" "${resolve_target}")"; then
    install_user_packages "${owner}"
    append_build_retry_install_records "${resolve_target}"
    exit 0
  fi

  log "Error: unable to resolve TeX Live package for ${resolve_target}" >&2
  exit 1
fi

resolved_packages=()
if [[ ${#source_files[@]} -gt 0 ]]; then
  while IFS=: read -r kind logical_name; do
    [[ -n "${kind}" && -n "${logical_name}" ]] || continue

    filename="$(module_filename "$kind" "$logical_name")"
    if latexctl_local_project_file_exists "${filename}"; then
      continue
    fi

    if kpsewhich "$filename" >/dev/null 2>&1; then
      continue
    fi

    if resolved_name="$(resolve_package_owner "$kind" "$logical_name" "$filename")"; then
      resolved_packages+=("${resolved_name}")
    else
      log "Error: unable to resolve TeX Live package for ${filename}" >&2
      exit 1
    fi
  done < <(scan_tex_modules)
fi

if [[ ${#resolved_packages[@]} -eq 0 ]]; then
  : > "${PACKAGE_FILE}"
else
  printf '%s\n' "${resolved_packages[@]}" | LC_ALL=C sort -u > "${PACKAGE_FILE}"
fi

if [[ ${#source_files[@]} -eq 0 ]]; then
  log "No source files found; package scan is empty."
fi

log "Wrote package state to ${PACKAGE_FILE}."

mapfile -t required_packages < <(awk 'NF && $1 !~ /^#/' "${PACKAGE_FILE}" | LC_ALL=C sort -u)
mapfile -t inferred_tools < <(infer_required_tools)
if [[ ${#inferred_tools[@]} -eq 0 ]]; then
  : > "${TOOL_FILE}"
else
  printf '%s\n' "${inferred_tools[@]}" > "${TOOL_FILE}"
fi

log "Wrote tool state to ${TOOL_FILE}."

if [[ ${#required_packages[@]} -eq 0 ]]; then
  log "All detected packages are core/builtin; no user-mode package installation needed."
else
  if ! install_user_packages "${required_packages[@]}"; then
    exit 1
  fi
fi

mapfile -t required_tools < <(awk 'NF && $1 !~ /^#/' "${TOOL_FILE}" | LC_ALL=C sort -u)
if [[ ${#required_tools[@]} -eq 0 ]]; then
  log "No required non-relocatable tools detected."
  exit 0
fi

missing_tools=()
for tool in "${required_tools[@]}"; do
  if ! tlmgr info --only-installed "${tool}" >/dev/null 2>&1; then
    missing_tools+=("${tool}")
  fi
done

if [[ ${#missing_tools[@]} -eq 0 ]]; then
  log "All required non-relocatable tools are already installed."
  exit 0
fi

log "Installing missing non-relocatable tools: ${missing_tools[*]}"
if ! sudo tlmgr install "${missing_tools[@]}"; then
  unresolved_tools=()
  for tool in "${missing_tools[@]}"; do
    if ! tlmgr info --only-installed "${tool}" >/dev/null 2>&1; then
      unresolved_tools+=("${tool}")
    fi
  done

  if [[ ${#unresolved_tools[@]} -eq 0 ]]; then
    log "tlmgr returned a non-zero status, but all requested tools are now installed."
    exit 0
  fi

  log "Error: failed to install one or more non-relocatable tools:" >&2
  printf '  - %s\n' "${unresolved_tools[@]}" >&2
  exit 1
fi

log "Successfully installed missing non-relocatable tools."
