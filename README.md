# Tech Debt Collector

AI-powered semantic tech debt scanning for Ruby on Rails applications.

`tech_debt_collector` helps teams detect and track architectural debt that linters usually miss: duplicated business logic, leaked domain rules, dead code, and complexity hotspots. It runs in GitHub Actions, triages findings with an LLM, and creates deduplicated GitHub Issues using deterministic fingerprints.

## Why this gem exists

Traditional static analysis catches syntax and style problems. It usually does not catch semantic debt such as:

- Controller actions with embedded business workflows
- Similar business rules duplicated across different domains
- Logic that should be extracted into concerns/services/query objects
- Uncalled methods and high-complexity methods that increase maintenance cost

This gem combines static signals (`debride`, `flog`) plus LLM triage so you get fewer noisy alerts and more actionable refactor tasks.

## What gets installed

Running the install generator adds three project files:

| File                                      | Purpose                            |
| ----------------------------------------- | ---------------------------------- |
| `.github/workflows/ai_tech_debt_scan.yml` | Scheduled/manual CI runner         |
| `config/tech_debt_settings.yml`           | Scanner, model, and issue settings |
| `.github/prompts/tech_debt_analysis.md`   | System prompt for semantic triage  |

## Requirements

- Ruby >= 3.1
- Rails >= 7.0 (for the install generator)
- GitHub repository with Actions enabled
- OpenAI API key

## Installation

### 1) Add the gem

```ruby
# Gemfile
group :development do
  gem "tech-debt-collector", github: "TelosLabs/tech-debt-collector"
end
```

```sh
bundle install
```

### 2) Install project files

```sh
bin/rails generate tech_debt_collector:install
```

### 3) Configure GitHub secrets

Add this repository secret:

- `OPENAI_API_KEY`

`GITHUB_TOKEN` is provided automatically by GitHub Actions and is used for issue queries/creation.

## How it works

1. Collect static candidates from dead-code and complexity analyzers.
2. Read code snippets for candidate files.
3. Send candidates + snippets to the LLM for semantic triage.
4. Normalize findings and compute fingerprints.
5. Search GitHub Issues for existing fingerprints.
6. Create only new issues (idempotent behavior).

## Fingerprinting and deduplication

Each issue includes a hidden fingerprint comment in the body:

```html
<!-- tech_debt_fingerprint:<sha1> -->
```

The scanner checks open and closed issues for that fingerprint before creating a new issue.

- Default fingerprint input: `file_path + identifier + debt_type`
- `semantic_duplication` uses `canonical_pattern` when present

This prevents duplicate issues across repeated runs.

## Running locally

### Dry run (recommended first)

```sh
bundle exec tech-debt-collector --dry-run
```

Runs analysis and prints what would be created without calling the GitHub Issues API.

### Dry run without LLM

```sh
bundle exec tech-debt-collector --dry-run --skip-llm
```

Uses only static collectors (`debride`, `flog`) and skips semantic triage.

## GitHub Actions usage

The installed workflow supports:

- `schedule` (weekly by default)
- `workflow_dispatch` with optional `dry_run` input

Manual run example:

1. Open **Actions** in your repo
2. Select **AI Tech Debt Scan**
3. Click **Run workflow**
4. Set `dry_run=true` for safe validation

## Configuration reference

Main settings are in `config/tech_debt_settings.yml`.

Key sections:

- `llm`: provider/model/token env/temperature/token budget
- `analysis.paths` and `analysis.exclude_paths`: scan scope
- `analysis.debt_types`: per-debt toggles and thresholds
- `github.labels`, `github.issue_prefix`, `github.max_issues_per_run`
- `reporting.summary_path`: JSON summary output

`ai-detected` and `severity:*` labels are managed automatically by the gem. Keep `github.labels` for shared/static labels (for example `tech-debt`).

## CLI options

```sh
bundle exec tech-debt-collector [options]
```

| Option          | Description                      |
| --------------- | -------------------------------- |
| `--config PATH` | Path to settings YAML            |
| `--prompt PATH` | Path to semantic prompt markdown |
| `--dry-run`     | Do not create issues             |
| `--skip-llm`    | Skip semantic triage             |

## Troubleshooting

**`cannot load such file -- octokit`**

- Run with bundler: `bundle exec tech-debt-collector`

**LLM JSON parse errors (`unexpected end of input`)**

- Increase `llm.max_tokens`
- Reduce scanned scope in `analysis.paths`
- Keep `--dry-run` while tuning

**No issues created**

- Check `github.max_issues_per_run`
- Confirm findings are not duplicates by fingerprint
- Verify `GITHUB_TOKEN` has `issues: write` permission in workflow

**LLM provider errors**

- Verify `OPENAI_API_KEY` is present in repository secrets
- Confirm `llm.model` is a valid model for your account/project

## License

MIT
