#!/bin/bash
set -euo pipefail

FUZZ_DIR="${1:?Usage: dry_run.sh <fuzz_binaries_dir> <seeds_dir> <results_dir>}"
SEEDS_DIR="${2:?Usage: dry_run.sh <fuzz_binaries_dir> <seeds_dir> <results_dir>}"
RESULTS_DIR="${3:?Usage: dry_run.sh <fuzz_binaries_dir> <seeds_dir> <results_dir>}"
TIMEOUT="${SEED_TIMEOUT:-30}"

mkdir -p "$RESULTS_DIR"

crash_count=0
total=0

for binary in "$FUZZ_DIR"/*; do
    [ -f "$binary" ] && [ -x "$binary" ] || continue

    bname=$(basename "$binary")
    # Skip non-fuzz-target files
    case "$bname" in
        *.dict|*.options|*.labels|*.cfg|*.txt|*.sh|*.py) continue ;;
        afl-*|llvm-symbolizer) continue ;;
    esac

    for seed in "$SEEDS_DIR"/*.bin; do
        [ -f "$seed" ] || continue
        sname=$(basename "$seed" .bin)
        result_file="$RESULTS_DIR/${bname}_${sname}.txt"

        [ -f "$result_file" ] && continue
        total=$((total + 1))

        echo "[*] Testing $bname with $sname..."

        set +e
        ASAN_OPTIONS="detect_leaks=0,abort_on_error=1" \
        timeout "$TIMEOUT" "$binary" "$seed" > /dev/null 2> "$RESULTS_DIR/.stderr_tmp"
        exit_code=$?
        set -e

        if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then
            echo "  [!] CRASH: $bname with $sname (exit=$exit_code)"
            mv "$RESULTS_DIR/.stderr_tmp" "$result_file"
            crash_count=$((crash_count + 1))
        else
            rm -f "$RESULTS_DIR/.stderr_tmp"
        fi
    done
done

echo ""
echo "[+] Dry run complete: $crash_count crashes out of $total tests"

# Write summary JSON
python3 -c "
import json, sys
print(json.dumps({
    'total_tests': $total,
    'crashes': $crash_count,
}))
" > "$RESULTS_DIR/summary.json"
