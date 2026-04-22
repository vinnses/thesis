#!/usr/bin/env bash

latexctl_ctan_mirror_file() {
  local repo_root

  repo_root="$(latexctl_repo_root)"
  printf '%s\n' "${repo_root}/latexctl/ctan-mirrors.txt"
}

latexctl_ctan_fallback_mirror() {
  printf '%s\n' "https://mirror.ctan.org/systems/texlive/tlnet"
}

latexctl_ctan_resolve_mirror() {
  local mirror_file
  local configured

  if [[ -n "${CTAN_MIRROR:-}" ]]; then
    printf '%s\n' "${CTAN_MIRROR}"
    return 0
  fi

  mirror_file="$(latexctl_ctan_mirror_file)"
  if [[ -f "${mirror_file}" ]]; then
    configured="$(
      awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { print; exit }
      ' "${mirror_file}"
    )"
    if [[ -n "${configured}" ]]; then
      printf '%s\n' "${configured}"
      return 0
    fi
  fi

  latexctl_ctan_fallback_mirror
}
