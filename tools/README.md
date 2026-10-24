# tools/

## cli_snapshot.ps1 — CLI 契约快照回归

把 `bin\winagent.exe` 的确定性命令跑一遍、规整成 JSON、和基线逐字段比对。用来在改完引擎后确认"没改坏"，替代手敲命令 + 肉眼看 JSON。

```powershell
# 建立/刷新基线（改动前跑）
powershell -File tools\cli_snapshot.ps1 -Mode Capture

# 比对（改动后跑），有差异时列出字段路径并 exit 1
powershell -File tools\cli_snapshot.ps1 -Mode Compare
```

- 规格：`tools\snapshot_specs\core_cli.json`（`entries[].args` 是命令行，`keep` 只保留契约字段以剔除前景窗口/缓存等波动数据，`expect` 是固定断言，`out_ext` 会追加 `--out` 并校验文件魔数与大小，`allow_not_ok` 允许该条目的响应是 `ok:false`——用于 `--help` 这类按契约必须非执行、但仍要盯住输出的命令）
- 基线：`artifacts\snapshot_baseline\<spec>\*.json`；本次运行结果：`artifacts\build\snapshot_run\<spec>\*.json`（故意放在 `build` 下，同步脚本排除该目录）
- 现有条目：`version`、`permission_status`、`policy_check_desktop_click`、`screenshot_region_png`、`visible_help_contract_desktop_move`（锁 `--help` 的 `argument_contract` 与全部 `non_executing` 安全字段）、`screenshot_full_png`
- 退出码：`0` 全过，`1` 有差异或断言失败

## 编译并行

`build.ps1` 的 `cl.exe` 调用带 `/MP`（按核数并行编译）。实测 24 核机器上一次全量 winagent 编译由 79s 降到见 `artifacts\build\elapsed_mp.txt`。