#!/usr/bin/env python3
import json
import re
import shutil
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

    # Collect crashes from both dry_run and fuzz subdirs
    seen = {}
    for subdir in ["dry_run", "fuzz"]:
        scan_dir = results_dir / subdir
        if not scan_dir.exists():
            continue
        for report_file in sorted(scan_dir.glob("*.txt")):
            if report_file.name == "summary.json":
                continue
            content = report_file.read_text(errors="replace")
            backtrace = parse_backtrace(content)
            if not backtrace:
                continue

            bt_hash = hash_backtrace(backtrace)
            crash_type = detect_crash_type(content)
            key = f"{bt_hash}_{crash_type}"

            bin_file = report_file.with_suffix(".bin")

            if key not in seen:
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
                    "from_dry_run": subdir == "dry_run",
                    "from_fuzz": subdir == "fuzz",
                    "report_file": str(report_file),
                    "input_file": str(bin_file) if bin_file.exists() else None,
                }
            else:
                seen[key]["triggered_by"].append(report_file.name)
                if subdir == "fuzz":
                    seen[key]["from_fuzz"] = True
                else:
                    seen[key]["from_dry_run"] = True

    # Collect hangs (no ASAN report, just the input)
    hangs = []
    fuzz_dir = results_dir / "fuzz"
    if fuzz_dir.exists():
        for hang_file in sorted(fuzz_dir.glob("*_hang_*.bin")):
            hangs.append({
                "file": hang_file.name,
                "path": str(hang_file),
            })

    # Build deduplicated PoC export directory
    pocs_dir = results_dir / "pocs"
    crashes_dir = pocs_dir / "crashes"
    hangs_dir = pocs_dir / "hangs"
    crashes_dir.mkdir(parents=True, exist_ok=True)
    hangs_dir.mkdir(parents=True, exist_ok=True)

    for crash in seen.values():
        h = crash["hash"][:12]
        if crash.get("input_file") and Path(crash["input_file"]).exists():
            shutil.copy2(crash["input_file"], crashes_dir / f"{h}_input.bin")
        if crash.get("report_file") and Path(crash["report_file"]).exists():
            shutil.copy2(crash["report_file"], crashes_dir / f"{h}_report.txt")

    for hang in hangs:
        if Path(hang["path"]).exists():
            safe_name = hang["file"].replace(":", "_").replace(",", "_")
            shutil.copy2(hang["path"], hangs_dir / safe_name)

    report = {
        "project": project,
        "unique_crashes": list(seen.values()),
        "hangs": hangs,
        "summary": {
            "total_unique_crashes": len(seen),
            "asan_unique": sum(1 for c in seen.values() if c["type"] == "asan"),
            "from_dry_run": sum(1 for c in seen.values() if c["from_dry_run"]),
            "from_fuzz": sum(1 for c in seen.values() if c["from_fuzz"]),
            "total_hangs": len(hangs),
        },
    }

    output_path = results_dir / "report.json"
    output_path.write_text(json.dumps(report, indent=2))

    # Also save a copy in pocs/
    (pocs_dir / "report.json").write_text(json.dumps(report, indent=2))

    print(json.dumps(report["summary"], indent=2))


if __name__ == "__main__":
    main()
