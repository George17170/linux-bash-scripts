# linux-bash-scripts

A collection of production-oriented bash scripts built for DevOps and QA automation workflows. Each script targets a real pain point in CI/CD pipelines, local development environments, and project maintenance.

## Scripts

### `pipeline_health_check.sh`
Validates CI/CD pipeline prerequisites before a run. Checks for required tools, environment variables, Docker daemon status, Dockerfile quality, and git state. Prevents mid-pipeline failures from missing config or environment drift.

```bash
./scripts/pipeline_health_check.sh
./scripts/pipeline_health_check.sh --env staging --report
```

**Checks include:** Git, Python, Docker, Terraform presence and versions · Docker daemon running · Required env vars (DockerHub, Azure, Slack) · Dockerfile HEALTHCHECK and non-root USER · GitHub Actions workflow presence · Disk space · Uncommitted changes

---

### `log_analyzer.sh`
Parses CI/CD or application log files and surfaces errors, warnings, test results, and timing data. Supports Pytest output, Docker build logs, and general application logs. Outputs a structured summary and saves a report file.

```bash
./scripts/log_analyzer.sh logs/build.log
./scripts/log_analyzer.sh logs/test_run.log --errors-only
./scripts/log_analyzer.sh logs/deploy.log --json
./scripts/log_analyzer.sh logs/app.log --tail 500
```

**Flags:** `--errors-only` · `--json` (structured JSON output) · `--tail <n>` (last n lines only)

---

### `docker_cleanup.sh`
Removes stopped containers, dangling images, unused volumes, and build cache. Safe for regular local use. Aggressive mode also removes all unused images. Dry-run mode shows what would be deleted without removing anything.

```bash
./scripts/docker_cleanup.sh
./scripts/docker_cleanup.sh --dry-run
./scripts/docker_cleanup.sh --aggressive --yes
```

**Flags:** `--dry-run` · `--aggressive` · `--yes` (skip confirmation, useful in CI)

---

### `env_validator.sh`
Validates that the local dev environment matches expected tool versions and project configuration. Catches version drift, missing `.env` keys, and port conflicts before they cause failures. Strict mode exits with a non-zero code if any version is below the minimum.

```bash
./scripts/env_validator.sh
./scripts/env_validator.sh --strict
./scripts/env_validator.sh --fix-hints
```

**Checks include:** Python 3.9+, Git 2.30+, Docker 24+, Terraform 1.5+, pip, Azure CLI, jq · `.env` vs `.env.example` key diff · Port availability (8080, 5432, 6379)

**Flags:** `--strict` (fail on version warnings) · `--fix-hints` (print install commands)

---

### `git_repo_audit.sh`
Audits a git repository for common maintenance issues: stale branches, unmerged branches, missing `.gitignore` entries, sensitive files accidentally tracked, large files in history, and missing release tags.

```bash
./scripts/git_repo_audit.sh .
./scripts/git_repo_audit.sh /path/to/project --stale-days 30
./scripts/git_repo_audit.sh . --report
```

**Flags:** `--stale-days <n>` (default: 60) · `--report` (save audit to logs/)

---

## Project structure

```
linux-bash-scripts/
├── scripts/
│   ├── pipeline_health_check.sh
│   ├── log_analyzer.sh
│   ├── docker_cleanup.sh
│   ├── env_validator.sh
│   └── git_repo_audit.sh
├── logs/                     # auto-created, gitignored
├── tests/
│   └── test_scripts.sh
└── README.md
```

## Setup

```bash
git clone https://github.com/George17170/linux-bash-scripts.git
cd linux-bash-scripts
chmod +x scripts/*.sh
```

No dependencies beyond standard bash utilities (`grep`, `awk`, `sed`, `find`) and the tools each script targets (Docker, Git, Terraform). All scripts are POSIX-compatible and tested on macOS and Ubuntu 22.04.

## Running tests

```bash
bash tests/test_scripts.sh
```

## Design principles

- **Fail loudly** — non-zero exit codes on failures, clearly labeled error messages
- **Dry-run first** — destructive scripts support `--dry-run` before committing
- **CI-friendly** — `--yes` and `--json` flags for scripted/non-interactive use
- **No external dependencies** — no Python, no Node, no package managers required

## License

MIT
