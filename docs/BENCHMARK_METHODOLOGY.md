# Benchmark Methodology

Current version: `v4.7.0`.

DesktopVisual benchmarks are evidence checks, not marketing claims.

## PASS, FAIL, SKIPPED

`PASS` means the benchmark observed the required behavior.

`FAIL` means the required behavior was not observed, or the task produced an unexpected error.

`SKIPPED` means the environment did not provide a safe prerequisite, such as OCR availability, an operator motion profile, or a target application. SKIPPED is not PASS.

## Safety

Benchmarks operate only authorized windows, generated local files, and `<project_root>\artifacts`. They do not manipulate existing user Notepad windows, external websites, credentials, payments, protected desktops, elevated windows, or sensitive applications.

## Reproduction

Run:

```powershell
D:\desktopvisual\build.ps1
D:\desktopvisual\selftest.ps1
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
D:\desktopvisual\export_evidence_pack.ps1
```

Outputs:

```text
D:\desktopvisual\artifacts\benchmark\benchmark_report.md
D:\desktopvisual\artifacts\benchmark\benchmark_summary.json
D:\desktopvisual\artifacts\evidence\DesktopVisual-v3.0.4-evidence-pack.zip
```

For v4 latency evidence run:

```powershell
D:\desktopvisual\latency_benchmark.ps1
D:\desktopvisual\v4_rc_check.ps1
```

v4 outputs:

```text
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_results.json
D:\desktopvisual\artifacts\dev4.3.0\latency\latency_summary.md
D:\desktopvisual\artifacts\dev4.7.0\v4_release_candidate_report.md
```

## Metrics

`pass_rate_excluding_skipped` is calculated as PASS divided by non-SKIPPED tasks. It is useful for comparing runnable tasks, but it must be read together with the skipped reasons.

The benchmark also records task success rate, average duration, average step count, locator method counts, failure category counts, skipped reason counts, recovery success rate, and report completeness.

## Limits

Benchmarks show which scripted tasks passed, safely stopped, or skipped on the current machine. They do not prove general control of arbitrary Windows software.
