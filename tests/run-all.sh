#!/usr/bin/env bash
# Run every tests/*.test.sh; exit non-zero if any suite fails.
cd "$(dirname "$0")" || exit 1
rc=0
for t in ./*.test.sh; do
  echo "== $t"
  "$t" || rc=1
done
exit $rc
