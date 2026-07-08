# osv-fuzz

Automated fuzzing CI for finding "lost bugs" in OSV/oss-fuzz projects.

## How it works

1. **Seed Collection**: POC test cases from OSV vulnerability reports are collected and stored in `seeds/`
2. **Build**: Each project's fuzz targets are built with AFL++ instrumentation on GitHub Actions
3. **Dry Run**: Each POC seed is replayed against the latest fuzz targets to check if old bugs still crash
4. **Fuzz**: Non-crashing seeds are used as corpus for 30-minute AFL++ fuzzing sessions
5. **Report**: Crashes are deduplicated and reported as artifacts

## Repository Structure

```
.github/workflows/     # Per-project GitHub Actions workflows
seeds/{project}/       # POC seed binaries and manifest
scripts/               # Shared build, fuzz, and reporting scripts
results/               # Fuzzing results (artifacts)
```

## Running a workflow

Each project can be triggered manually via `workflow_dispatch` or runs weekly on schedule.

```bash
gh workflow run "Fuzz curl" --repo cla7aye15I4nd/osv-fuzz
```
