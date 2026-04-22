# Reusable LaTeX Workspace

Reusable environment for LaTeX projects with Docker Compose and Dev Container.

This repository keeps the **workspace/tooling** and also a default `tex/` directory to bootstrap projects.
You can replace the contents of `tex/` with another template/project when needed.

## Quick start

1. Copy environment variables:
   ```bash
   cp .env.example .env
   ```
   > `TEMPLATE_URL` is optional. If empty, the `entrypoint` seeds `tex/` from the internal scaffold bundled in this repository.

   > `CTAN_MIRROR` is optional. If empty, build/runtime TeX Live operations use the first entry from `latexctl/ctan-mirrors.txt`.

   > `TEXLIVE` controls the build profile (`minimal` or `full`).

   > `COMPOSE_PROJECT_NAME` is optional. If unset, Compose usually derives it from the directory name, and the container hostname follows that project name.
2. Start the service:
   ```bash
   docker compose up -d --build texservice
   ```
3. Open a shell in the container:
   ```bash
   docker compose exec texservice bash
   ```
4. Run `Makefile` targets as needed for your project.

## Repository structure

```text
.
├── latexctl/
│   ├── bin/
│   │   └── latexctl
│   ├── lib/
│   │   ├── bootstrap.sh
│   │   ├── build.sh
│   │   ├── classify.sh
│   │   ├── common.sh
│   │   ├── sync.sh
│   │   └── ziptex.sh
│   └── tests/
├── entrypoint.sh
├── .devcontainer/
│   └── devcontainer.json
├── Dockerfile
├── compose.yaml
├── .env.example
├── .gitignore
├── Makefile
└── README.md
```

> Note: the `tex/` directory is part of this template contract and represents the default starting point.
> In real projects, it can be replaced by other imported content.

## Utility scripts

- `entrypoint.sh`: root-level container entrypoint. It bootstraps `tex/` when needed and then delegates to the main command surface.
- `latexctl/bin/latexctl`: central command surface for LaTeX workspace operations.
  - `latexctl build`: cleans auxiliary files once at the start inside `tex/`, keeps only the current PDF plus a single `.previous.pdf` backup, runs smart sync, and wraps `latexmk` with bounded retry logic for TeX files and font metrics. When the build cannot recover automatically, it writes reduced diagnostics under `.latex-errors/`.
  - `latexctl sync`: scans `tex/` sources, resolves missing modules via TeX Live ownership data, and installs them.
  - `latexctl ziptex`: packages TeX sources for export.
  - `latexctl bootstrap`: initializes `tex/` when empty from the internal scaffold by default, or from `TEMPLATE_URL` when an explicit external override is provided.
  - `latexctl classify-error`: categorizes failure logs into user/project errors vs environment/runtime errors.
  - `latexctl ctan-mirror`: prints the selected CTAN `tlnet` repository after applying `CTAN_MIRROR` override and repo defaults.

## Smart sync and build workflow

The default flow is:

1. `make sync` runs `latexctl/bin/latexctl sync`.
2. The sync script scans `tex/` sources for document classes, packages, and package requests.
3. Each logical module name is checked with `kpsewhich`; missing modules are resolved against TeX Live metadata instead of a handwritten alias table.
4. Packages are written to `.used_packages`, and non-relocatable tools are written to `.used_tools`.
5. If a package or tool is still missing, the script installs it through the appropriate `tlmgr` mode.
6. `make build` runs `latexctl/bin/latexctl build`, which cleans aux files once at the beginning inside `tex/`, keeps one previous PDF copy, calls sync, compiles into `tex/` with `latexmk`, and retries when the log exposes a recoverable missing-file dependency (including `.tex` support files and `.tfm` font metrics).
7. Dynamic package installs triggered specifically by the build retry loop are appended to `.build_retry_installs`.

When the build still fails, the wrapper writes a reduced report to `.latex-errors/`:

- `.latex-errors/user-errors.log`: project/input mistakes, such as missing local files or assets.
- `.latex-errors/environment-errors.log`: environment/runtime issues, such as missing TeX assets or font metrics.
- `.latex-errors/summary.env`: compact machine-readable classification for follow-up tooling.

This does not suppress normal LaTeX output. It adds a smaller diagnostic surface so the actionable error is not buried in the full `latexmk` stream.

Project config files are supported when TeX Live metadata is ambiguous or when the project needs extra tools:

- `latexctl/package-overrides.conf`: manual package-owner overrides for ambiguous module/file resolution.
- `extra-tools.txt`: versioned extra tool names to install alongside the inferred tool set.

TeX packages are detected automatically from `tex/` sources and installed through `tlmgr --usermode`.
`extra-tools.txt` is only for external tools that are not reliably inferable from LaTeX source scanning, such as `chktex` and `latexindent`.
The `minimal` image keeps only the core build toolchain in the Dockerfile; tools listed in `extra-tools.txt` are installed on demand by the sync/build workflow.

## Compose + Dev Container

The main service is `texservice`.
The same service is used by Dev Container to keep terminal and VS Code behavior consistent.

Image tags are profile-based:

- `teximage:minimal`
- `teximage:full`

The Compose file does not pin `container_name`, so Docker can namespace containers naturally.
The container hostname follows `COMPOSE_PROJECT_NAME`; when that variable is unset, Compose usually derives the project name from the directory.

If `tex/` is empty and the provided `TEMPLATE_URL` is invalid/unreachable,
the container exits with an error and guidance to fix/remove `TEMPLATE_URL`.

## Make targets

Common commands:

```bash
make help
make sync
make test
make pdf
make watch
make clean
make lint
make ci
```

If imported content inside `tex/` has its own Makefile, it can be used directly for document-specific tasks.
The root Makefile remains the workspace orchestrator and default flow for this template.

`make pdf` and `make watch` keep successful intermediate files under `tex/` for faster iteration.
`make build` is the heavier recovery path: it cleans `tex/` first and then runs the smart dependency/install loop.

## Collaborative workflow

- Work on a feature branch.
- Integrate through Pull Requests.
- For `.tex` files, keep Semantic Linefeed (one sentence per line).
