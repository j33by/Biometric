#!/usr/bin/env bash
# The desktop app and the phone app must compute late / early minutes identically,
# so they share ONE file. This fails if the two copies drift apart.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if ! diff -u "$root/lib/core/schedule_calc.dart" "$root/teacher_app/lib/schedule_calc.dart"; then
  echo "schedule_calc.dart differs between lib/core and teacher_app/lib." >&2
  echo "Edit lib/core/schedule_calc.dart, then: cp lib/core/schedule_calc.dart teacher_app/lib/schedule_calc.dart" >&2
  exit 1
fi
echo "schedule_calc.dart is identical in both apps."
