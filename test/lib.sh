# shellcheck shell=bash
# Shared by test/run.sh and test/smoke.sh. Not executable on its own.
#
# Every rule's refusal keeps the same two-part contract, and both test scripts
# assert it:
#
#   - It opens a line with the rule's own name. Jobs from every config a consumer
#     lists land in one hook's job list, and lefthook prints their output in one
#     stream, so a refusal that does not name itself leaves the reader guessing
#     which of them spoke. The check is per line rather than on the first line
#     because lefthook frames job output with its own summary.
#   - The text says how to bypass. A hook that blocks a commit without saying how
#     to get past it once gets uninstalled.
#
# Checking this is the difference between knowing a rule rejected a message and
# knowing it told the person why. A quoting mistake in the refusal mangles the
# text and leaves the exit status at 1, so the status alone proves little.

# refusal_problem <rule> <output>
# Print what is wrong with <output> as a refusal from <rule> and return 1, or
# print nothing and return 0 when it keeps the contract.
refusal_problem() {
	local rule=$1 output=$2

	if [ -z "$output" ]; then
		printf 'rejected the message and printed nothing'
		return 1
	fi

	if ! printf '%s\n' "$output" | grep -q "^$rule: "; then
		printf 'no line of the refusal opens with "%s: "' "$rule"
		return 1
	fi

	case "$output" in
	*--no-verify*) ;;
	*)
		printf 'the refusal never says how to bypass it'
		return 1
		;;
	esac

	return 0
}
