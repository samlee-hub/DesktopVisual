# Expected Result

- Writes a small local test result under `artifacts\dogfood\powershell`.
- Reads that generated file through `winagent read-file`.
- Records PASS/SKIPPED/FAIL in a per-task JSON report.

The task must not run administrator commands, external network commands, credential access, or destructive filesystem operations.

