#!/usr/bin/env bash
# Commit for real, in a throwaway repo, and read the refusal off git's stderr.
#
# test/run.sh reads each rule's command out of `lefthook dump` and runs it under
# `sh`. That proves the check is right. It does not prove anybody ever sees it:
# between the rule file and the person committing sit lefthook's config merge,
# the hook script it installs, and whatever shell the platform hands that script.
# That stack is what differs between one machine and another, and it is the part
# a rule author cannot see from here.
#
# So this script installs the rules the way a consumer gets them, runs a real
# `git commit`, and checks both directions: a bad message is rejected and says
# why, a good one goes through.
#
# One fail fixture and one pass fixture per rule. The exhaustive pass is
# test/run.sh; this is the smoke.
#
# Usage:  test/smoke.sh
#         LEFTHOOK_BIN=/path/to/lefthook test/smoke.sh
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin=${LEFTHOOK_BIN:-lefthook}

# shellcheck source=test/lib.sh
. "$root/test/lib.sh"

if ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then
	echo "test/smoke.sh: lefthook not found. Install it, or set LEFTHOOK_BIN." >&2
	exit 2
fi

# The installed hook script looks lefthook up on PATH, not through LEFTHOOK_BIN.
# A binary given by path has to join PATH or the hook finds nothing and every
# commit passes — which would read here as a rule that stopped working.
case "$bin" in
*/*)
	bin_dir=$(cd -- "$(dirname -- "$bin")" && pwd)
	PATH="$bin_dir:$PATH"
	export PATH
	;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Colour codes would be quoted into every failure report below.
export NO_COLOR=1

failures=0
checks=0

report_failure() {
	echo "  FAIL  $1" >&2
	failures=$((failures + 1))
}

indent_output() {
	printf '%s\n' "$1" | sed 's/^/          /' >&2
}

git init -q -- "$work"
cd -- "$work"
git config user.email lefthook-rules@example.invalid
git config user.name 'lefthook-rules test'
git config commit.gpgsign false

# The rules are copied in rather than pointed at. `extends:` resolves its paths
# against the repo lefthook is running in, and a consumer's copy likewise lives
# inside its own repo, under .git/info/lefthook-remotes.
cp -R -- "$root/rules" rules
{
	echo 'extends:'
	for rule_file in rules/*.yml; do
		echo "  - $rule_file"
	done
} >lefthook.yml

"$bin" install >/dev/null

# Each attempt needs its own staged change: a commit that goes through consumes
# the one before it.
stage_a_change() {
	printf 'change %s\n' "$checks" >"file-$checks.txt"
	git add -A .
}

# One commit before the tests, so the rules run against a repo with a HEAD. A
# rule's `skip: [merge, rebase]` asks git about the commit in progress, and on an
# empty repo that question has no answer.
stage_a_change
git commit --no-verify -q -m 'Add the first file'

for rule_file in "$root"/rules/*.yml; do
	rule=$(basename -- "$rule_file" .yml)
	fixtures="$root/test/fixtures/$rule"
	echo "$rule"

	# Named rather than globbed: every rule is installed for every commit here, so
	# a good message has to be one that no other rule objects to either.
	#
	# `pass-verbose-diff.txt` earns its place next to the plain one. It is the
	# only fixture that reaches the `sed` truncating the message at the scissors
	# line, and that expression is where a rule's backslashes live. Backslash and
	# double quote are the two characters lefthook's Windows command line can
	# swallow, so the one construct still holding backslashes gets walked through
	# the real hook rather than reasoned about.
	pass_fixtures=()
	for name in pass-plain.txt pass-verbose-diff.txt; do
		[ -f "$fixtures/$name" ] && pass_fixtures+=("$fixtures/$name")
	done
	if [ ${#pass_fixtures[@]} -eq 0 ]; then
		for fixture in "$fixtures"/pass-*.txt; do
			[ -f "$fixture" ] || continue
			pass_fixtures=("$fixture")
			break
		done
	fi

	fail_fixture=""
	for fixture in "$fixtures"/fail-*.txt; do
		[ -f "$fixture" ] || continue
		fail_fixture=$fixture
		break
	done

	if [ -z "$fail_fixture" ] || [ ${#pass_fixtures[@]} -eq 0 ]; then
		report_failure "$rule: no fixture to smoke test with"
		continue
	fi

	checks=$((checks + 1))
	stage_a_change
	if output=$(git commit -F "$fail_fixture" 2>&1); then
		report_failure "$rule: git accepted $(basename -- "$fail_fixture")"
		indent_output "$output"
	elif ! problem=$(refusal_problem "$rule" "$output"); then
		report_failure "$rule: $problem"
		indent_output "$output"
	else
		echo "  ok    rejected $(basename -- "$fail_fixture"), and said why"
	fi

	for pass_fixture in "${pass_fixtures[@]}"; do
		checks=$((checks + 1))
		stage_a_change
		if output=$(git commit -F "$pass_fixture" 2>&1); then
			echo "  ok    committed $(basename -- "$pass_fixture")"
		else
			report_failure "$rule: the hooks rejected $(basename -- "$pass_fixture")"
			indent_output "$output"
		fi
	done
done

echo
if [ "$failures" -gt 0 ]; then
	echo "$failures failure(s) in $checks commits" >&2
	exit 1
fi
echo "$checks commits behaved"
