# wall-e

AI-powered semantic tech debt scanning for Ruby on Rails applications.

`wall-e` helps teams detect and track architectural debt that linters usually miss: duplicated business logic, leaked domain rules, dead code, and complexity hotspots. It runs in GitHub Actions, triages findings with an LLM, and creates deduplicated GitHub Issues using deterministic fingerprints.

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
| `.github/workflows/wall_e_scan.yml` | Scheduled/manual CI runner         |
| `config/wall_e_settings.yml`        | Scanner, model, and issue settings |
| `.github/prompts/wall_e_analysis.md`| System prompt for semantic triage  |

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
  gem "wall-e", github: "TelosLabs/wall-e"
end
```

```sh
bundle install
```

### 2) Install project files

```sh
bin/rails generate wall_e:install
```

### 3) Configure GitHub secrets

Add this repository secret:

- `OPENAI_API_KEY`

`GITHUB_TOKEN` is provided automatically by GitHub Actions and is used for issue queries/creation and, by default, for assignment/comment operations when no explicit assignment token is configured.

Optional (recommended if you enable auto-assignment or use Copilot-based assignment rules):

- `AGENT_ASSIGN_TOKEN` — Personal Access Token from a licensed Copilot/Cursor user for assignment/comment operations. If this is not set, the action will fall back to `GITHUB_TOKEN`, which may not be sufficient for some assignment providers (for example, Copilot assignment may require a user PAT).

## How it works

1. Collect static candidates from dead-code and complexity analyzers.
2. Read code snippets for candidate files.
3. Send candidates + snippets to the LLM for semantic triage with Rails-focused risk checks.
4. Normalize findings and compute fingerprints.
5. Search GitHub Issues for existing fingerprints.
6. Create only new issues (idempotent behavior).

### Triage priorities

The default prompt prioritizes high-impact Rails risks when they appear in scanned snippets:

- SQL/data safety issues and fragile query construction
- Race/concurrency risks in read-check-write flows
- Unvalidated LLM output crossing trust boundaries
- Enum/status completeness gaps across branches/allowlists

These are still emitted using the existing debt taxonomy (`fat_controller`, `leaked_business_logic`, `semantic_duplication`, `missing_concern`, `dead_code`, `high_complexity`) to keep output stable.

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
bundle exec wall-e --dry-run
```

Runs analysis and prints what would be created without calling the GitHub Issues API.

### Dry run without LLM

```sh
bundle exec wall-e --dry-run --skip-llm
```

Uses only static collectors (`debride`, `flog`) and skips semantic triage.

## GitHub Actions usage

The installed workflow supports:

- `schedule` (weekly by default)
- `workflow_dispatch` with optional `dry_run` input

Manual run example:

1. Open **Actions** in your repo
2. Select **wall-e Scan**
3. Click **Run workflow**
4. Set `dry_run=true` for safe validation

## Auto-assign AI agents

You can optionally auto-dispatch newly created issues to an AI coding agent right after issue creation.

Add this to `config/wall_e_settings.yml`:

```yaml
auto_assign:
  enabled: true
  agent: "copilot" # "copilot" | "cursor"
  token_env: "AGENT_ASSIGN_TOKEN"
  filters:
    min_severity: "medium" # low, medium, high
    debt_types: [] # empty means all debt types
  cursor_prompt: |
    Analyze and fix this tech debt issue. Read the description for file path,
    debt type, and suggested refactoring approach. Open a PR when done.
```

How each mode works:

- `agent: "copilot"`: assigns the issue to `copilot`
- `agent: "cursor"`: posts a `cursor` comment with your configured prompt

Recommended setup:

1. Keep `enabled: false` first and run one scan to validate issue quality.
2. Add `AGENT_ASSIGN_TOKEN` as a repo/org secret.
3. Enable with a conservative filter (`min_severity: "high"`), then relax later.

### Copilot setup

- Enable Copilot coding agent for the repository/org.
- Create a PAT from a Copilot-licensed user with minimal permissions (Issues write + Metadata read).
- Store PAT in `AGENT_ASSIGN_TOKEN`.

### Cursor setup

- Install the Cursor GitHub App on the org/repo.
- Use a PAT from a Cursor team user in `AGENT_ASSIGN_TOKEN`.
- Tune `cursor_prompt` to enforce your branch/PR/testing conventions.

Assignment is best-effort: if assignment fails, issue creation still succeeds.

## Configuration reference

Main settings are in `config/wall_e_settings.yml`.

Key sections:

- `llm`: provider/model/token env/temperature/token budget
- `llm.retry_attempts` and `llm.retry_base_delay_seconds`: exponential backoff for OpenAI 429s
- `analysis.paths` and `analysis.exclude_paths`: scan scope
- `analysis.debt_types`: per-debt toggles and thresholds
- `github.labels`, `github.issue_prefix`, `github.max_issues_per_run`
- `reporting.summary_path`: JSON summary output
- `auto_assign`: optional post-creation dispatch to Copilot or Cursor

`ai-detected` and `severity:*` labels are managed automatically by the gem. Keep `github.labels` for shared/static labels (for example `tech-debt`).

The semantic triage behavior is defined in `.github/prompts/wall_e_analysis.md` (installed by the generator), so teams can tune strictness and wording for their codebase.

## Interpreting scores

`score` is numeric for sorting/prioritization, but not all debt types use the same scale:

- `high_complexity`: complexity metric (for example flog score) relative to configured threshold
- `semantic_duplication`: estimated duplicated impact/lines
- `dead_code`: count-based dead-code signal
- Other types: heuristic impact estimate (0-100)

## CLI options

```sh
bundle exec wall-e [options]
```

| Option          | Description                      |
| --------------- | -------------------------------- |
| `--config PATH` | Path to settings YAML            |
| `--prompt PATH` | Path to semantic prompt markdown |
| `--dry-run`     | Do not create issues             |
| `--skip-llm`    | Skip semantic triage             |

## Troubleshooting

**`cannot load such file -- octokit`**

- Run with bundler: `bundle exec wall-e`

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

**OpenAI 429 rate limits**

- Increase `llm.retry_attempts` and/or `llm.retry_base_delay_seconds`
- Reduce scanned scope in `analysis.paths` or run in dry mode while tuning

## TODO

- [ ] Enhance fingerprint generation to avoid creating duplicate issues for the same code, given AI-generated titles.
- [ ] Define a strategy to handle existing issues that are closed (the issue appeared again or it was originally ignored)

## License

MIT
