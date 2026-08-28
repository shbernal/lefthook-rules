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

### Attribution settings do not cover the session trailer

Turning attribution off in Claude Code takes more than one setting, and the
settings do not compose. `includeCoAuthoredBy: false` and
`attribution: { commit: "", pr: "" }` drop the `Co-Authored-By` trailer and the
`Generated with Claude Code` footer. Neither touches the `Claude-Session:`
trailer that cloud and Remote Control sessions add. That one reads
`attribution: { sessionUrl: false }`, or the environment variable
`CLAUDE_CODE_SUPPRESS_SESSION_ATTRIBUTION=1`, and nothing else.

An empty `commit` does not merely fail to suppress the session URL either. It
promotes it: with no attribution text to prepend, the trailer goes from a line
under `Co-Authored-By` to the only attribution in the commit. People who had
opted out months earlier got it anyway, in histories they then had to rewrite.
[anthropics/claude-code#77830][issue-77830] has the detail and the settings that
do work.

So set all three. The rule is the backstop for the next channel that ships with
a switch of its own: it reads the message about to be committed, so it does not
care which setting was supposed to have covered it.

[issue-77830]: https://github.com/anthropics/claude-code/issues/77830

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
test/run.sh      # every rule against every fixture message
test/smoke.sh    # one real commit per rule, through an installed hook
```

Each rule carries fixture messages under `test/fixtures/<rule>/`. `pass-*.txt`
must be accepted and `fail-*.txt` must be rejected. `test/run.sh` reads each rule
through `lefthook dump`, so it tests the command lefthook would run rather than a
copy of it.

`test/smoke.sh` covers what that cannot see. It installs the rules in a throwaway
repo, runs a real `git commit`, and reads the refusal back off git's stderr — so
it exercises the config merge, the installed hook and the platform's shell as
well as the rule. Both scripts check the refusal text, not only the exit status.

GitHub Actions runs both on `ubuntu-latest` and `windows-latest` on every push.

## Add a rule

Read [AGENTS.md](AGENTS.md). Four invariants constrain what a rule may do, and
one of them is not obvious: a rule cannot ship a helper script.
