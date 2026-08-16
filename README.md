# lefthook-rules

Shared [lefthook](https://lefthook.dev) rules, consumed as a remote config.

One repo holds the rules. Each project opts into the ones it wants with four
lines in its own `lefthook.yml`. Lefthook fetches this repo, caches it under
`.git/info/lefthook-remotes/`, and merges the rules into the project's hooks.

## Use

Add this to a project's `lefthook.yml`:

```yaml
remotes:
  - git_url: https://github.com/shbernal/lefthook-rules
    ref: v1
    configs:
      - rules/no-ai-attribution.yml
    refetch_frequency: 24h
```

Then run `lefthook install`. Lefthook fetches a remote on `install`, not on
`dump`, so a fresh clone needs that command before the rules exist. Most projects
already run it from a `prepare` script.

The project keeps its own jobs. Local jobs and remote jobs merge into one list on
the same hook, and local jobs run first.

## Rules

| Rule | Hook | What it rejects |
| --- | --- | --- |
| `rules/no-ai-attribution.yml` | `commit-msg` | Agent-attribution trailers and footers: `Co-Authored-By: Claude`, `Claude-Session:`, a `claude.ai/code/session_…` URL, `Generated with Claude Code`, and the same forms for ChatGPT, Copilot, Codex, Cursor, Devin, Gemini and Aider. |
| `rules/no-shell-quoting-leak.yml` | `commit-msg` | A PowerShell here-string delimiter that leaked into the message because the wrong shell dialect was used: a line that is only `@`, `@'` or `@"`, an opener glued to the subject, or a closer at the end of a line. |

## Versions

Pin `ref:` to a tag, never to a branch. A branch means that any push here changes
what every project runs.

- A new rule file is additive. It does not move a tag, because nothing consumes a
  rule until a project names it in `configs:`.
- A rename, a removal, or a tightened pattern is breaking. It gets the next major
  tag.
- `v1` moves only for a fix that no consumer would refuse, such as a false
  positive.

Without `refetch_frequency` or `refetch: true`, the cached copy is permanent and a
fix never reaches a project.

## Test

```sh
test/run.sh
```

Each rule carries fixture messages under `test/fixtures/<rule>/`. `pass-*.txt`
must be accepted and `fail-*.txt` must be rejected. The runner reads each rule
through `lefthook dump`, so it tests the command lefthook would run rather than a
copy of it. GitHub Actions runs the same script on every push.

## Add a rule

Read [AGENTS.md](AGENTS.md). Four invariants constrain what a rule may do, and
one of them is not obvious: a rule cannot ship a helper script.
