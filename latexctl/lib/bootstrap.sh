#!/usr/bin/env bash

latexctl_bootstrap_is_tex_empty() {
  local tex_dir="$1"

  if [[ ! -d "${tex_dir}" ]]; then
    return 0
  fi

  if find "${tex_dir}" -mindepth 1 ! -name '.gitkeep' -print -quit | grep -q .; then
    return 1
  fi

  return 0
}

latexctl_bootstrap_fetch_template() {
  local tex_dir="$1"
  local template="$2"

  mkdir -p "${tex_dir}"

  if [[ -d "${template}" ]]; then
    latexctl_log "Copying local scaffold: ${template}"
    rm -f "${tex_dir}/.gitkeep"
    cp -a "${template}/." "${tex_dir}/"
    return 0
  fi

  if [[ "${template}" == *.zip ]]; then
    local tmp_zip
    local tmp_dir
    tmp_zip="$(mktemp)"
    tmp_dir="$(mktemp -d)"
    latexctl_log "Fetching zip template: ${template}"
    curl -fL "${template}" -o "${tmp_zip}"
    unzip -q "${tmp_zip}" -d "${tmp_dir}"
    rm -f "${tmp_zip}"

    if [[ $(find "${tmp_dir}" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] && [[ -d "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1)" ]]; then
      cp -a "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1)/." "${tex_dir}/"
    else
      cp -a "${tmp_dir}/." "${tex_dir}/"
    fi
    rm -rf "${tmp_dir}"
    return 0
  fi

  if [[ "${template}" == *.tar.gz || "${template}" == *.tgz ]]; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    latexctl_log "Fetching tar template: ${template}"
    curl -fL "${template}" | tar -xz -C "${tmp_dir}"

    if [[ $(find "${tmp_dir}" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] && [[ -d "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1)" ]]; then
      cp -a "$(find "${tmp_dir}" -mindepth 1 -maxdepth 1)/." "${tex_dir}/"
    else
      cp -a "${tmp_dir}/." "${tex_dir}/"
    fi
    rm -rf "${tmp_dir}"
    return 0
  fi

  latexctl_log "Cloning git template: ${template}"
  rm -f "${tex_dir}/.gitkeep"
  rmdir "${tex_dir}" 2>/dev/null || true
  git clone --depth 1 "${template}" "${tex_dir}"
  rm -rf "${tex_dir}/.git"
}

latexctl_bootstrap() {
  local repo_root
  local workspace_dir
  local tex_dir
  local default_scaffold
  local template_url

  repo_root="$(latexctl_repo_root)"
  workspace_dir="${repo_root}"
  tex_dir="${workspace_dir}/tex"
  default_scaffold="${repo_root}/latexctl/scaffold/tex"
  template_url="${TEMPLATE_URL:-}"

  if latexctl_bootstrap_is_tex_empty "${tex_dir}"; then
    if [[ -n "${template_url}" ]]; then
      latexctl_log "tex/ is empty; initializing from template: ${template_url}"
    else
      latexctl_log "tex/ is empty; initializing from internal scaffold: ${default_scaffold}"
      template_url="${default_scaffold}"
    fi

    if ! latexctl_bootstrap_fetch_template "${tex_dir}" "${template_url}"; then
      latexctl_log "Error: failed to initialize tex/ from template: ${template_url}" >&2
      latexctl_log "Hint: set TEMPLATE_URL to a valid git/zip/tar URL, or leave it unset to use the internal scaffold." >&2
      return 1
    fi
  else
    latexctl_log "tex/ is not empty; skipping template fetch."
  fi

  #"${repo_root}/latexctl/bin/latexctl" build
  echo "run make build to install dependences"
}
