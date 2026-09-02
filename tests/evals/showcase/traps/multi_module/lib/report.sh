#!/usr/bin/env bash
# Print "total: N" where N is the integer sum of all arguments.
total=0
for n in "$@"; do
  total="$total$n"                     # bug: string concatenation, not addition
done
echo "total: $total"
