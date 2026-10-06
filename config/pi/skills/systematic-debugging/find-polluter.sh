#!/usr/bin/env bash
# Bisection script to find which test creates unwanted files/state
# Usage: ./find-polluter.sh <file_or_dir_to_check> <test_pattern>
# Example: ./find-polluter.sh 'tmp/state.db' 'src/**/*.test.ts'
# Run it from the root of a throwaway clone: the tests it runs may write anywhere.
# The pollution target must not exist before the run.

set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <file_to_check> <test_pattern>"
  echo "Example: $0 'tmp/state.db' 'src/**/*.test.ts'"
  exit 1
fi

POLLUTION_CHECK="$1"
TEST_PATTERN="$2"

# Tests that run git must reach only this throwaway clone, never the repo that
# launched us (a git hook exports GIT_DIR and friends to its children).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_COMMON_DIR GIT_NAMESPACE
here="$(pwd -P)"
gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
case "$gitdir" in
  "$here"/*) ;;
  *) echo "Run this from the root of a throwaway clone (git resolves to: ${gitdir:-none})." >&2; exit 2 ;;
esac

if [ -e "$POLLUTION_CHECK" ]; then
  echo "$POLLUTION_CHECK already exists: pick a target that the tests create, or remove it first." >&2
  exit 2
fi

echo "🔍 Searching for test that creates: $POLLUTION_CHECK"
echo "Test pattern: $TEST_PATTERN"
echo ""

# Get list of test files (find . emits ./-prefixed paths, so accept the
# pattern written with or without a leading ./)
TEST_PATTERN="${TEST_PATTERN#./}"
# find -path can't match '**/' against zero directory levels, so a pattern
# like src/**/*.test.ts would skip src/top.test.ts; also try the pattern
# with '**/' collapsed to cover files directly under the base directory.
TEST_FILES=$(find . \( -path "./$TEST_PATTERN" -o -path "./${TEST_PATTERN//\*\*\//}" \) | sort -u)
if [ -z "$TEST_FILES" ]; then
  TOTAL=0
else
  TOTAL=$(printf '%s\n' "$TEST_FILES" | wc -l | tr -d ' ')
fi

echo "Found $TOTAL test files"
echo ""

if [ "$TOTAL" -eq 0 ]; then
  echo "No test files match $TEST_PATTERN: nothing was tested." >&2
  exit 2
fi

COUNT=0
for TEST_FILE in $TEST_FILES; do
  COUNT=$((COUNT + 1))

  # Skip if pollution already exists
  if [ -e "$POLLUTION_CHECK" ]; then
    echo "⚠️  Pollution already exists before test $COUNT/$TOTAL"
    echo "   Skipping: $TEST_FILE"
    continue
  fi

  echo "[$COUNT/$TOTAL] Testing: $TEST_FILE"

  # Run the test
  npm test "$TEST_FILE" > /dev/null 2>&1 || true

  # Check if pollution appeared
  if [ -e "$POLLUTION_CHECK" ]; then
    echo ""
    echo "🎯 FOUND POLLUTER!"
    echo "   Test: $TEST_FILE"
    echo "   Created: $POLLUTION_CHECK"
    echo ""
    echo "Pollution details:"
    ls -la "$POLLUTION_CHECK"
    echo ""
    echo "To investigate:"
    echo "  npm test $TEST_FILE    # Run just this test"
    echo "  cat $TEST_FILE         # Review test code"
    exit 1
  fi
done

echo ""
echo "✅ No polluter found - all tests clean!"
exit 0
