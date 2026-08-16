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
# Usage:  test/run.sh
#         LEFTHOOK_BIN=/path/to/lefthook test/run.sh
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin=${LEFTHOOK_BIN:-lefthook}

if ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then
	echo "test/run.sh: lefthook not found. Install it, or set LEFTHOOK_BIN." >&2
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
	done < <(LEFTHOOK_CONFIG="$rule_file" "$bin" dump --format json | python3 "$root/test/extract-jobs.py")

	if [ ${#jobs[@]} -eq 0 ]; then
		report_failure "$rule: the config defines no job with a run command"
		continue
	fi

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
