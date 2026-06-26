# Edge Dogfood

Tests Microsoft Edge with a LOCAL HTML page only.

## Expected Outcome
- Edge opens a local HTML test page.
- Input field receives text via DesktopVisual.
- Button click triggers JavaScript.
- Result verified via OCR/UIA/file read.

## Failure Cases
- Edge not found 鈫?SKIPPED.
- Local HTML page not served 鈫?FAIL.
- Cannot verify result 鈫?FAIL.

## Safety
- Opens ONLY local HTML file (D:\desktopvisual\artifacts\dogfood\edge\page.html).
- Does NOT access internet, login, or read user browser data.
- Edge windows opened by this test are closed.
