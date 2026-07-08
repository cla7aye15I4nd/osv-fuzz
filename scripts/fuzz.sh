#!/bin/bash
set -euo pipefail

FUZZ_DIR="${1:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
SEEDS_DIR="${2:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
DRY_RUN_DIR="${3:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
FUZZ_RESULTS_DIR="${4:?Usage: fuzz.sh <fuzz_binaries_dir> <seeds_dir> <dry_run_results_dir> <fuzz_results_dir>}"
FUZZ_DURATION="${FUZZ_DURATION:-1800}"

mkdir -p "$FUZZ_RESULTS_DIR"

# First pass: count valid fuzz targets
valid_targets=()
for binary in "$FUZZ_DIR"/*; do
    [ -f "$binary" ] && [ -x "$binary" ] || continue

    bname=$(basename "$binary")
    case "$bname" in
        *.dict|*.options|*.labels|*.cfg|*.txt|*.sh|*.py|*.zip|*.json|*.a|*.o|*.so|*.cnf|*.pem|*.der) continue ;;
        afl-*|llvm-symbolizer) continue ;;
    esac

    if ! AFL_NO_UI=1 AFL_SKIP_CPUFREQ=1 timeout 5 afl-showmap -m none -o /dev/null -- "$binary" /dev/null > /dev/null 2>&1; then
        echo "  [!] SKIP $bname — not AFL-instrumented or crashes on startup"
        continue
    fi

    valid_targets+=("$binary")
done

num_targets=${#valid_targets[@]}
if [ "$num_targets" -eq 0 ]; then
    echo "[!] No valid fuzz targets found"
    echo '{"new_crashes":0,"fuzz_duration":'"$FUZZ_DURATION"',"targets_attempted":0,"targets_succeeded":0}' > "$FUZZ_RESULTS_DIR/summary.json"
    exit 0
fi

# Split total duration evenly across targets (minimum 60s per target)
per_target=$((FUZZ_DURATION / num_targets))
if [ "$per_target" -lt 60 ]; then
    per_target=60
fi

echo "[+] Found $num_targets valid targets, ${per_target}s each (total budget: ${FUZZ_DURATION}s)"

new_crashes=0
targets_attempted=0
targets_succeeded=0

for binary in "${valid_targets[@]}"; do
    bname=$(basename "$binary")

    input_dir="$FUZZ_RESULTS_DIR/${bname}_input"
    output_dir="$FUZZ_RESULTS_DIR/${bname}_output"
    afl_log="$FUZZ_RESULTS_DIR/${bname}_afl.log"
    mkdir -p "$input_dir" "$output_dir"

    seed_count=0
    for seed in "$SEEDS_DIR"/*.bin; do
        [ -f "$seed" ] || continue
        sname=$(basename "$seed" .bin)
        if [ -f "$DRY_RUN_DIR/${bname}_${sname}.txt" ]; then
            continue
        fi
        cp "$seed" "$input_dir/"
        seed_count=$((seed_count + 1))
    done

    if [ "$seed_count" -eq 0 ]; then
        echo "min" > "$input_dir/minimal_seed"
        seed_count=1
    fi

    echo "[*] Fuzzing $bname with $seed_count seeds for ${per_target}s..."
    targets_attempted=$((targets_attempted + 1))

    set +e
    start_time=$(date +%s)
    AFL_SKIP_CPUFREQ=1 \
    AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    AFL_NO_UI=1 \
    timeout "$per_target" \
        afl-fuzz -i "$input_dir" -o "$output_dir" -m none -- "$binary" @@ \
        > "$afl_log" 2>&1
    fuzz_exit=$?
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    set -e

    if [ "$elapsed" -lt 30 ] && [ "$fuzz_exit" -ne 124 ]; then
        echo "  [!] WARN: $bname exited after ${elapsed}s (expected ${per_target}s)"
        echo "  [!] afl-fuzz exit code: $fuzz_exit"
        tail -20 "$afl_log" 2>/dev/null | sed 's/^/  [afl] /'
    else
        targets_succeeded=$((targets_succeeded + 1))
        echo "  [+] $bname fuzzed for ${elapsed}s (exit: $fuzz_exit)"
    fi

    # Check for crashes
    crash_dir="$output_dir/default/crashes"
    if [ -d "$crash_dir" ]; then
        for crash_file in "$crash_dir"/id:*; do
            [ -f "$crash_file" ] || continue
            crash_name=$(basename "$crash_file" | tr ':,' '__')
            result_file="$FUZZ_RESULTS_DIR/${bname}_fuzz_${crash_name}.txt"

            set +e
            ASAN_OPTIONS="detect_leaks=0,abort_on_error=1" \
            timeout 30 "$binary" "$crash_file" > /dev/null 2> "$result_file"
            replay_exit=$?
            set -e

            if [ $replay_exit -ne 0 ] && [ $replay_exit -ne 124 ]; then
                echo "  [!] NEW CRASH: $bname from fuzzing"
                cp "$crash_file" "$FUZZ_RESULTS_DIR/${bname}_fuzz_${crash_name}.bin"
                echo "$crash_name" > "$FUZZ_RESULTS_DIR/${bname}_fuzz_${crash_name}.bin.orig_name"
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
            hang_name=$(basename "$hang_file" | tr ':,' '__')
            cp "$hang_file" "$FUZZ_RESULTS_DIR/${bname}_hang_${hang_name}.bin"
            echo "  [!] HANG: $bname from fuzzing"
        done
    fi

    rm -rf "$input_dir" "$output_dir"
done

echo ""
echo "[+] Fuzzing complete: $new_crashes new crashes found"
echo "[+] Targets: $targets_succeeded/$targets_attempted fuzzed successfully"

python3 -c "
import json
print(json.dumps({
    'new_crashes': $new_crashes,
    'fuzz_duration': $FUZZ_DURATION,
    'per_target_duration': $per_target,
    'targets_attempted': $targets_attempted,
    'targets_succeeded': $targets_succeeded,
}))
" > "$FUZZ_RESULTS_DIR/summary.json"
