#!/usr/bin/env bash
# Run every rule against its fixture messages.
#
# A rule is a regex, and a regex gets false positives. A shared rule that starts
# rejecting good commits breaks every consumer at once, and it breaks them at the
# moment they commit, which is the worst moment to debug a hook. So each rule
# carries fixtures: `pass-*.txt` must be accepted, `fail-*.txt` must be rejected.
#
# The runner never holds its own copy of a rule's command. It points
# LEFTHOOK_CONFIG at one rule file and reads back what `lefthook dump` parsed, so
# a rule is tested exactly as lefthook would run it — and a rule whose YAML does
# not parse fails here rather than in a consumer.
#
# An exit status alone is a weak assertion. A rule that rejects a message but
# prints nothing useful has failed the person committing, and a quoting mistake
# in the refusal text mangles the message while leaving the status at 1. So a
# rejection is also checked against the contract every rule keeps: the first line
# names the rule, and the text says how to bypass.
#
# Usage:  test/run.sh
#         LEFTHOOK_BIN=/path/to/lefthook test/run.sh
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin=${LEFTHOOK_BIN:-lefthook}

# shellcheck source=test/lib.sh
. "$root/test/lib.sh"

if ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then
	echo "test/run.sh: lefthook not found. Install it, or set LEFTHOOK_BIN." >&2
	exit 2
fi

# Git Bash on Windows has no `python3`, only whatever the runner put on PATH.
python=python3
command -v "$python" >/dev/null 2>&1 || python=python
if ! command -v "$python" >/dev/null 2>&1; then
	echo "test/run.sh: no python3 or python on PATH." >&2
	exit 2
fi

failures=0
checks=0

report_failure() {
	echo "  FAIL  $1" >&2
	failures=$((failures + 1))
}

for rule_file in "$root"/rules/*.yml; do
	rule=$(basename "$rule_file" .yml)
	fixtures="$root/test/fixtures/$rule"
	echo "$rule"

	# An untested rule is the failure mode this runner exists to prevent, so a
	# missing fixture directory is an error rather than a skip.
	if [ ! -d "$fixtures" ]; then
		report_failure "$rule: no fixture directory at test/fixtures/$rule"
		continue
	fi

	jobs=()
	while IFS= read -r line; do
		jobs+=("$line")
	done < <(LEFTHOOK_CONFIG="$rule_file" "$bin" dump --format json | "$python" "$root/test/extract-jobs.py")

	if [ ${#jobs[@]} -eq 0 ]; then
		report_failure "$rule: the config defines no job with a run command"
		continue
	fi

	# A rule that holds a double quote anywhere is broken on Windows, and it is
	# broken in a way no fixture can catch here: lefthook runs a job as
	# `sh.exe -c "<the whole script>"` and escapes nothing in between, so the
	# first `"` closes that argument and sh gets a truncated script. Under `sh`
	# on this machine the same rule passes. Only this check stands between a
	# stray quote and a consumer on Windows.
	for entry in "${jobs[@]}"; do
		job=${entry%%$'\t'*}
		checks=$((checks + 1))
		case $(printf '%s' "${entry#*$'\t'}" | base64 -d) in
		*'"'*) report_failure "$rule/$job: the command holds a double quote, which truncates it on Windows" ;;
		*) echo "  ok    $job holds no double quote" ;;
		esac
	done

	# Both directions have to be covered. A rule with only fail- fixtures proves
	# it rejects something and nothing about what it lets through.
	for prefix in pass fail; do
		if ! compgen -G "$fixtures/$prefix-*.txt" >/dev/null; then
			report_failure "$rule: no $prefix-*.txt fixture"
		fi
	done

	for fixture in "$fixtures"/*.txt; do
		name=$(basename "$fixture")
		case "$name" in
		pass-*) accept=true ;;
		fail-*) accept=false ;;
		*)
			report_failure "$rule/$name: a fixture name must start with pass- or fail-"
			continue
			;;
		esac

		for entry in "${jobs[@]}"; do
			job=${entry%%$'\t'*}
			command=$(printf '%s' "${entry#*$'\t'}" | base64 -d)
			# `{1}` is the placeholder lefthook fills with git's commit-message path.
			command=${command//\{1\}/$fixture}

			checks=$((checks + 1))
			output=$(cd "$root" && sh -c "$command" 2>&1) && status=0 || status=$?

			if [ "$accept" = true ] && [ "$status" -ne 0 ]; then
				report_failure "$rule/$job on $name: rejected a message it should accept"
				[ -n "$output" ] && echo "$output" | sed 's/^/          /' >&2
			elif [ "$accept" = false ] && [ "$status" -eq 0 ]; then
				report_failure "$rule/$job on $name: accepted a message it should reject"
			elif [ "$accept" = false ] && ! problem=$(refusal_problem "$rule" "$output"); then
				report_failure "$rule/$job on $name: $problem"
				echo "$output" | sed 's/^/          /' >&2
			else
				echo "  ok    $job on $name"
			fi
		done
	done
done

echo
if [ "$failures" -gt 0 ]; then
	echo "$failures failure(s) in $checks checks" >&2
	exit 1
fi
echo "$checks checks passed"
