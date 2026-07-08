#!/bin/bash
set -euo pipefail

FUZZ_DIR="${1:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
SEEDS_DIR="${2:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
DRY_RUN_DIR="${3:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
FUZZ_RESULTS_DIR="${4:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
FUZZ_DURATION="${FUZZ_DURATION:-1800}"

mkdir -p "$FUZZ_RESULTS_DIR"

new_crashes=0

for binary in "$FUZZ_DIR"/*; do
    [ -f "$binary" ] && [ -x "$binary" ] || continue

    bname=$(basename "$binary")
    case "$bname" in
        *.dict|*.options|*.labels|*.cfg|*.txt|*.sh|*.py|*.zip|*.json) continue ;;
        afl-*|llvm-symbolizer) continue ;;
    esac

    input_dir="$FUZZ_RESULTS_DIR/${bname}_input"
    output_dir="$FUZZ_RESULTS_DIR/${bname}_output"
    mkdir -p "$input_dir" "$output_dir"

    # Use seeds that did NOT crash in dry run as corpus
    seed_count=0
    for seed in "$SEEDS_DIR"/*.bin; do
        [ -f "$seed" ] || continue
        sname=$(basename "$seed" .bin)
        # Skip seeds that crashed during dry run
        if [ -f "$DRY_RUN_DIR/${bname}_${sname}.txt" ]; then
            continue
        fi
        cp "$seed" "$input_dir/"
        seed_count=$((seed_count + 1))
    done

    if [ "$seed_count" -eq 0 ]; then
        # If all seeds crash, still try fuzzing with a minimal corpus
        echo "min" > "$input_dir/minimal_seed"
        seed_count=1
    fi

    echo "[*] Fuzzing $bname with $seed_count seeds for ${FUZZ_DURATION}s..."

    # Try afl-fuzz first
    set +e
    AFL_SKIP_CPUFREQ=1 \
    AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    AFL_NO_UI=1 \
    timeout "$FUZZ_DURATION" \
        afl-fuzz -i "$input_dir" -o "$output_dir" -m none -- "$binary" @@ \
        > /dev/null 2>&1
    fuzz_exit=$?
    set -e

    # Check for crashes
    crash_dir="$output_dir/default/crashes"
    if [ -d "$crash_dir" ]; then
        for crash_file in "$crash_dir"/id:*; do
            [ -f "$crash_file" ] || continue
            crash_name=$(basename "$crash_file")
            result_file="$FUZZ_RESULTS_DIR/${bname}_fuzz_${crash_name}.txt"

            set +e
            ASAN_OPTIONS="detect_leaks=0,abort_on_error=1" \
            timeout 30 "$binary" "$crash_file" > /dev/null 2> "$result_file"
            replay_exit=$?
            set -e

            if [ $replay_exit -ne 0 ] && [ $replay_exit -ne 124 ]; then
                echo "  [!] NEW CRASH: $bname from fuzzing"
                # Also save the crashing input
                cp "$crash_file" "$FUZZ_RESULTS_DIR/${bname}_fuzz_${crash_name}.bin"
                new_crashes=$((new_crashes + 1))
            else
                rm -f "$result_file"
            fi
        done
    fi

    # Check for hangs
    hang_dir="$output_dir/default/hangs"
    if [ -d "$hang_dir" ]; then
        for hang_file in "$hang_dir"/id:*; do
            [ -f "$hang_file" ] || continue
            hang_name=$(basename "$hang_file")
            cp "$hang_file" "$FUZZ_RESULTS_DIR/${bname}_hang_${hang_name}.bin"
            echo "  [!] HANG: $bname from fuzzing"
        done
    fi

    # Cleanup large fuzzing output to save space
    rm -rf "$input_dir" "$output_dir"
done

echo ""
echo "[+] Fuzzing complete: $new_crashes new crashes found"

python3 -c "
import json
print(json.dumps({
    'new_crashes': $new_crashes,
    'fuzz_duration': $FUZZ_DURATION,
}))
" > "$FUZZ_RESULTS_DIR/summary.json"
