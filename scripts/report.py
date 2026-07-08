#!/usr/bin/env python3
import json
import re
import sys
from hashlib import md5
from pathlib import Path


def parse_backtrace(report: str) -> tuple[tuple[str, str], ...]:
    backtrace = []
    stack_pattern = re.compile(r"#\d+ 0x[0-9a-f]+ in (.+) (/\S+)")
    for line in report.splitlines():
        match = stack_pattern.search(line)
        if match:
            function = match.group(1)
            source = match.group(2)
            if "llvm-project/compiler-rt" not in source:
                backtrace.append((function, source))
    return tuple(backtrace)


def hash_backtrace(backtrace):
    s = "#".join(f"{func}${src}" for func, src in backtrace)
    return md5(s.encode()).hexdigest()


def detect_crash_type(report: str) -> str:
    if "ERROR: AddressSanitizer" in report:
        return "asan"
    if "ERROR: libFuzzer" in report:
        return "libfuzzer"
    return "unknown"


def main():
    if len(sys.argv) < 2:
        print("Usage: report.py <results_dir> [project_name]")
        sys.exit(1)

    results_dir = Path(sys.argv[1])
    project = sys.argv[2] if len(sys.argv) > 2 else results_dir.name

    seen = {}
    for report_file in sorted(results_dir.glob("*.txt")):
        if report_file.name == "summary.json":
            continue
        content = report_file.read_text(errors="replace")
        backtrace = parse_backtrace(content)
        if not backtrace:
            continue

        bt_hash = hash_backtrace(backtrace)
        crash_type = detect_crash_type(content)
        key = f"{bt_hash}_{crash_type}"

        if key not in seen:
            is_dry_run = "_fuzz_" not in report_file.name
            crash_summary = ""
            for line in content.splitlines():
                if "ERROR:" in line:
                    crash_summary = line.strip()
                    break

            seen[key] = {
                "hash": bt_hash,
                "type": crash_type,
                "crash_summary": crash_summary,
                "stack_frames": [f"{func} {src}" for func, src in backtrace[:5]],
                "triggered_by": [report_file.name],
                "from_dry_run": is_dry_run,
                "from_fuzz": not is_dry_run,
            }
        else:
            seen[key]["triggered_by"].append(report_file.name)
            if "_fuzz_" in report_file.name:
                seen[key]["from_fuzz"] = True
            else:
                seen[key]["from_dry_run"] = True

    report = {
        "project": project,
        "unique_crashes": list(seen.values()),
        "summary": {
            "total_unique": len(seen),
            "asan_unique": sum(1 for c in seen.values() if c["type"] == "asan"),
            "from_dry_run": sum(1 for c in seen.values() if c["from_dry_run"]),
            "from_fuzz": sum(1 for c in seen.values() if c["from_fuzz"]),
        },
    }

    output_path = results_dir / "report.json"
    output_path.write_text(json.dumps(report, indent=2))
    print(json.dumps(report["summary"], indent=2))


if __name__ == "__main__":
    main()
