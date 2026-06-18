# Public Release Guide

Use this package from the extracted package root. The runtime binary is `bin\winagent.exe`.

Run `selftest.ps1` for a package smoke check. Run the public release safety tests before distributing a copied package.

The release safety policy is context based. It does not block only because a page contains test, quiz, or exam. It stops when explicit assessment integrity rules, active protection, or credential requirements make automation inappropriate.

F12 stops the current task without closing winagent.
