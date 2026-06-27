FROM debian:bookworm-slim AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG TEXUSER=texuser
ARG TEXUID=1000
ARG TEXGID=1000
ARG CTAN_MIRROR=
ARG LATEXCTL_REPOSITORY=https://github.com/vinnses/latexctl.git
ARG LATEXCTL_REF=main

ENV USERNAME=${TEXUSER}
ENV CTAN_MIRROR=${CTAN_MIRROR}
ENV LATEXCTL_REPOSITORY=${LATEXCTL_REPOSITORY}
ENV LATEXCTL_REF=${LATEXCTL_REF}
ENV TEXMFHOME=/texdata/texmf-home
ENV TEXMFVAR=/texdata/texmf-var
ENV TEXMFCONFIG=/texdata/texmf-config
ENV TERM=xterm-256color
ENV EDITOR=vim
ENV VISUAL=vim
ENV PAGER=less
ENV PATH=/usr/local/texlive/bin/x86_64-linux:${PATH}:${TEXMFHOME}/scripts:/workspace/bin

WORKDIR /workspace

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  bash \
  bash-completion \
  ca-certificates \
  curl \
  fd-find \
  file \
  fontconfig \
  git \
  gnupg \
  iputils-ping \
  jq \
  less \
  libfile-homedir-perl \
  libunicode-linebreak-perl \
  libyaml-tiny-perl \
  locales \
  make \
  nano \
  netcat-openbsd \
  openssh-client \
  perl \
  procps \
  ripgrep \
  rsync \
  sudo \
  tar \
  tree \
  unzip \
  vim \
  wget \
  xz-utils && \
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
  locale-gen en_US.UTF-8 && \
  rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN groupadd --gid "${TEXGID}" "${USERNAME}" && \
  useradd --uid "${TEXUID}" --gid "${TEXGID}" -m -s /bin/bash "${USERNAME}" && \
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
  mkdir -p /workspace /texdata/texmf-home /texdata/texmf-var /texdata/texmf-config && \
  chown -R "${TEXUID}:${TEXGID}" /workspace /texdata

RUN cat >> /etc/bash.bashrc <<'EOF'

# Workspace container defaults.
if [ -n "${PS1:-}" ]; then
  alias ls='ls --color=auto'
  alias ll='ls -alF --color=auto'
  alias la='ls -A --color=auto'
  alias l='ls -CF --color=auto'
  alias grep='grep --color=auto'
  alias egrep='egrep --color=auto'
  alias fgrep='fgrep --color=auto'

  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  fi
fi
EOF

COPY --chmod=0755 bin/latexctl /usr/local/bin/latexctl

ENTRYPOINT ["/workspace/entrypoint.sh"]

FROM base AS minimal

RUN set -eux; \
  ctan_repo="$(LATEXCTL_PROJECT_ROOT=/workspace latexctl ctan-mirror)"; \
  tmpdir="$(mktemp -d)"; \
  curl -fsSL "${ctan_repo%/}/install-tl-unx.tar.gz" -o "${tmpdir}/install-tl.tar.gz"; \
  tar -xzf "${tmpdir}/install-tl.tar.gz" -C "${tmpdir}"; \
  installer_dir="$(find "${tmpdir}" -maxdepth 1 -type d -name 'install-tl-*' | head -n1)"; \
  { echo 'selected_scheme scheme-basic'; echo 'TEXDIR /usr/local/texlive'; echo 'option_doc 0'; echo 'option_src 0'; } > "${tmpdir}/texlive.profile"; \
  "${installer_dir}/install-tl" -profile "${tmpdir}/texlive.profile"; \
  rm -rf "${tmpdir}"; \
  tlmgr option repository "${ctan_repo}"; \
  tlmgr install latexmk

USER ${USERNAME}
CMD ["bash"]

FROM base AS full

RUN set -eux; \
  ctan_repo="$(LATEXCTL_PROJECT_ROOT=/workspace latexctl ctan-mirror)"; \
  tmpdir="$(mktemp -d)"; \
  curl -fsSL "${ctan_repo%/}/install-tl-unx.tar.gz" -o "${tmpdir}/install-tl.tar.gz"; \
  tar -xzf "${tmpdir}/install-tl.tar.gz" -C "${tmpdir}"; \
  installer_dir="$(find "${tmpdir}" -maxdepth 1 -type d -name 'install-tl-*' | head -n1)"; \
  { echo 'selected_scheme scheme-full'; echo 'TEXDIR /usr/local/texlive'; echo 'option_doc 0'; echo 'option_src 0'; } > "${tmpdir}/texlive.profile"; \
  "${installer_dir}/install-tl" -profile "${tmpdir}/texlive.profile"; \
  rm -rf "${tmpdir}"; \
  tlmgr option repository "${ctan_repo}"

USER ${USERNAME}
CMD ["bash"]
