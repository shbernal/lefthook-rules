# Working on lefthook-rules

This repo is consumed by other repos over lefthook's `remotes:` mechanism. A
change here reaches every project that pins the tag, and it reaches them at the
moment somebody commits. Treat every edit as a release.

## Commands

```sh
test/run.sh                                  # all rules against all fixtures
test/smoke.sh                                # one real commit per rule, end to end
LEFTHOOK_BIN=./node_modules/.bin/lefthook test/run.sh   # when lefthook is not on PATH
```

Those two scripts are the whole gate. There is nothing to build and nothing to
lint.

`test/run.sh` reads each rule's command out of `lefthook dump` and runs it under
`sh`, once per fixture. `test/smoke.sh` installs the rules in a throwaway repo
and runs a real `git commit`, one rejected message and one accepted message per
rule. The second exists because everything between the rule file and the person
committing — the config merge, the installed hook, the platform's shell — is
invisible to the first, and that layer is exactly what differs between a Linux
machine and a Windows one. CI runs both on `ubuntu-latest` and `windows-latest`.

## Invariants

**One file per rule, in `rules/`, named for the rule and not for the hook.**
Lefthook merges jobs from every config a consumer lists, appending them to the
hook's job list. So a per-rule file lets a project take one rule and leave
another. A per-hook file would make every message rule all-or-nothing, and it
would cost nothing to avoid.

**The file path is the public API.** Consumers name it in `configs:`. A rename
breaks them silently — lefthook reports a missing config, not a missing rule. To
retire a name, keep the old file for one major version and cut a new tag.

**The job `name:` equals the file stem.** Every rule's jobs land in one shared job
list, so two rules with a job called `check` would be indistinguishable in the
output.

**A rule is self-contained shell.** A remote job runs with the working directory
set to the *consumer's* repo root. This repo's own files are unreachable from it,
including `scripts/`, so there is no helper to call. Verified: a job running
`ls scripts/x.mjs` from a remote config resolves the path against the consumer
and fails.

Inline shell is also the fast form. Measured on a commit-msg check: about 3 ms
for `sed | git stripspace | grep`, against about 19 ms for the same logic as a
Node script, against about 26 ms for lefthook's own startup.

**A rule's shell holds no double quotes.** Inside double quotes a shell still
expands `$`, a backtick and a backslash, and a rule's text is full of the
punctuation that trips them. Patterns go in single quotes, refusal text goes in a
`<<'MSG'` here-doc with a quoted delimiter — that expands nothing and needs no
escaping. The one place a `"` may appear is inside a regex, where it is a
character to match rather than a quote; say so in a comment. `'\''` is the only
escape any rule should need, and only when a single-quoted pattern must contain a
single quote.

**A refusal names its rule and says how to bypass.** Jobs from every config a
consumer lists print into one stream, so a rule opens a line with its own name:
`no-ai-attribution: …`. The text ends with `git commit --no-verify`, because a
hook that blocks a commit without saying how to get past it once gets
uninstalled. `test/run.sh` and `test/smoke.sh` both assert this — an exit status
alone would pass a refusal whose text came out mangled.

**Every rule carries fixtures, in both directions.** `test/run.sh` fails a rule
with no fixture directory, and fails one with no `pass-*.txt` or no `fail-*.txt`.
A rule with only failing fixtures proves that it rejects something and nothing
about what it lets through.

**No bundles and no presets.** A `recommended.yml` that pulled in other rules
cannot work: `extends:` inside a remote config resolves its paths against the
consumer, not against this repo. The rule table in the README is the index.

## Add a rule

1. Write `rules/<name>.yml`. One job, named `<name>`.
2. Add `skip:` for the states where the message is not yours, usually
   `[merge, rebase]`.
3. Write fixtures under `test/fixtures/<name>/`. Cover the near misses, not only
   the obvious hit — a `git commit -v` message carries the diff, and prose about
   the banned thing is not the banned thing.
4. Run `test/run.sh`, then `test/smoke.sh`.
5. Prove the rule can fail. Add a fixture that should be rejected but is not, and
   watch the runner report it. A rule that cannot fail is a rule that is not
   wired up.
6. Add a row to the README table.

## Releasing

Tags are the version. See the README for what is additive and what is breaking.

```sh
git tag -f v1 && git push -f origin v1     # only for a fix no consumer would refuse
git tag v2 && git push origin v2           # for anything breaking
```

Announce nothing. A consumer picks the change up on its next refetch, within
`refetch_frequency`.

## Commits

Describe the change on its own terms, imperative mood. This repo's own
`lefthook.yml` extends `rules/no-ai-attribution.yml`, so it enforces its own rule
on itself.
