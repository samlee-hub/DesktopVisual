# DesktopVisual Benchmarks

DesktopVisual benchmarks are repeatable evidence tasks. They distinguish:

- `PASS`: required behavior was observed.
- `FAIL`: required behavior was not observed.
- `SKIPPED`: the environment did not provide a safe prerequisite.

Run:

```powershell
D:\desktopvisual\benchmark_matrix.ps1
D:\desktopvisual\benchmark_selftest.ps1
D:\desktopvisual\export_evidence_pack.ps1
```

Reports are written under `artifacts\benchmark`.

Benchmark safety uses `observe-locate-act-verify`, safety stop rules, no unrestricted desktop control, and no sensitive flows.
