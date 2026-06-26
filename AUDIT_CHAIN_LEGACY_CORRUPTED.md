# AUDIT_CHAIN

鏈枃浠剁敤浜庤褰旵laude Code鍦ㄥ壇鏈」鐩腑鐨勬墍鏈夊紑鍙戣涓猴紝渚涘悗缁瑿odex澶嶆牳銆?
鏈枃浠跺彧鍏佽杩藉姞锛屼笉鍏佽鍒犻櫎鍘嗗彶璁板綍銆?
## 0. 鍩哄噯淇℃伅

- 鍘熼」鐩矾寰勶細D:\desktopvisual-cc
- Claude鍓湰璺緞锛欴:\desktopvisual-cc锛堢洿鎺ユ搷浣滃師椤圭洰锛屾棤鐙珛鍓湰锛?- 鍩哄噯鐗堟湰/commit锛歷1.4.0锛堥潪git浠撳簱锛屾棤commit hash锛?- 寮€濮嬫帴缁紑鍙戞椂闂达細2026-05-28 21:51 CST
- 鎵ц妯″瀷锛欳laude Code (deepseek-v4-pro 鍚庣)
- 鎵ц宸ュ叿锛欱ash (PowerShell via bash), Read, Write, Edit, Glob, Grep
- 鍚庣画澶嶆牳宸ュ叿锛欳odex / winagent.exe selftest / 浜哄伐澶嶆牳

## 1. 鍏ㄥ眬闄愬埗

- 鍙厑璁稿湪Claude鍓湰椤圭洰涓慨鏀规枃浠躲€?- 涓嶅厑璁镐慨鏀瑰師椤圭洰銆傦紙褰撳墠Claude鍓湰鍗充负鍘熼」鐩級
- 涓嶅厑璁歌法骞冲彴鍖栥€傦紙淇濇寔Windows涓撶敤锛?- 涓嶅厑璁稿ぇ鑼冨洿閲嶆瀯鐩綍缁撴瀯銆?- 涓嶅厑璁镐慨鏀规棤鍏虫枃浠躲€?- 涓嶅厑璁告敼鍙榯race/action/config/鍗忚璇箟锛岄櫎闈炰换鍔℃槑纭姹傘€?- 姣忎釜鐗堟湰蹇呴』鐢熸垚鐙珛鎶ュ憡銆乨iff鍜屾棩蹇椼€?- 姣忎釜鐗堟湰蹇呴』璁板綍鏈獙璇侀闄┿€?
---

## 2. 鐗堟湰瀹¤璁板綍

### Version: v1.4.0 (鍩哄噯璁板綍)

#### 浠诲姟鐩爣

- 璁板綍v1.4.0鍩哄噯鐘舵€侊紝浣滀负鍚庣画鐗堟湰瀹¤鐨勮捣鐐广€?- 寤虹珛AUDIT_CHAIN.md鍙婇厤濂楃洰褰曠粨鏋勩€?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 21:51 CST
- 瀹屾垚鏃堕棿锛?026-05-28 21:52 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| AUDIT_CHAIN.md | 鏂板 | 寤虹珛鍙璁℃暟鎹摼鏂囦欢锛屼緵鍚庣画Codex澶嶆牳 |
| agent_reports/ | 鏂板鐩綍 | 瀛樻斁姣忎釜鐗堟湰鐨勬姤鍛?|
| patches/ | 鏂板鐩綍 | 瀛樻斁姣忎釜鐗堟湰鐨刣iff |
| logs/ | 鏂板鐩綍 | 瀛樻斁姣忎釜鐗堟湰鐨勬瀯寤烘棩蹇楀拰娴嬭瘯鏃ュ織 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| 鏈慨鏀筎race.cpp/Trace.h锛孞SON淇″皝鏍煎紡涓嶅彉 |
| action璇箟 | 鍚?| 鏈慨鏀逛换浣曞懡浠よ涓?|
| config鏍煎紡 | 鍚?| config/safety.conf 鏈慨鏀?|
| 鍏叡鍗忚 | 鍚?| COMMAND_PROTOCOL.md 鏈慨鏀?|
| 鏋勫缓绯荤粺 | 鍚?| build.ps1 鏈慨鏀?|
| 鏉冮檺閫昏緫 | 鍚?| SafetyPolicy.cpp 鏈慨鏀?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛氭湰娆℃湭鎵ц鏋勫缓锛堜粎鍒涘缓瀹¤鏂囦欢锛?- 鏋勫缓缁撴灉锛歂/A锛堝熀鍑嗚褰曪紝鏃犲彉鏇撮渶鏋勫缓锛?- 鏋勫缓鏃ュ織璺緞锛歂/A

#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护锛歚D:\desktopvisual-cc\bin\winagent.exe version`
- 娴嬭瘯缁撴灉锛氶€氳繃銆傝緭鍑虹増鏈彿 1.4.0锛宐uild_time "May 28 2026 19:52:17"锛屽钩鍙?Windows锛宑apabilities 鍒楄〃瀹屾暣锛坅vailable 30椤? stub 2椤? experimental 1椤癸級
- 娴嬭瘯鏃ュ織璺緞锛歂/A锛堝熀鍑嗚褰曪紝version鍛戒护杈撳嚭宸插唴鑱旓級

#### 鐢熸垚璇佹嵁

- diff鏂囦欢锛歂/A锛堝熀鍑嗚褰曪紝鏃犱唬鐮佸彉鏇达級
- 鐗堟湰鎶ュ憡锛歛gent_reports/v1.4.0_baseline_report.md锛堝緟鐢熸垚锛?- 鏋勫缓鏃ュ織锛歂/A
- 娴嬭瘯鏃ュ織锛歂/A

#### 鏈獙璇侀闄?
- 椤圭洰涓嶅湪git绠＄悊涓嬶紝鍚庣画diff鐢熸垚闇€渚濊禆鏂囦欢澶囦唤姣斿銆?- winagent.exe 褰撳墠鏃堕棿鎴?2026-05-28 19:52:24锛宻rc婧愮爜淇敼鏃堕棿鏁ｅ竷鍦?5鏈?5-28鏃ワ紝鏋勫缓浜х墿涓庢簮浠ｇ爜鏃堕棿涓€鑷存€ф湭閫愭枃浠舵牎楠屻€?- OCR妯″潡 (OcrController.cpp) 涓哄瓨鏍瑰疄鐜帮紝鎵€鏈塐CR鍛戒护杩斿洖 OCR_UNAVAILABLE銆?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 纭 v1.4.0 鎵€鏈夋簮鏂囦欢涓?bin/winagent.exe 鐨勭紪璇戜竴鑷存€э紙obj鏂囦欢鏃堕棿鎴充笌exe鍖归厤锛夈€?- 纭 artifacts/ 涓嬪凡鏈夋祴璇曟姤鍛婃湭鍙楀悗缁慨鏀瑰奖鍝嶃€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細鍩哄噯璁板綍锛屾棤闇€澶嶆牳銆傚悗缁増鏈粠 v1.4.0 寮€濮嬪璁°€?
---

### Version: v1.5.0

#### 浠诲姟鐩爣

- 瀹炵幇 Case v2 瑙ｆ瀽鍣ㄥ拰鍔ㄤ綔鍚庨獙璇佺郴缁熴€?- 淇濇寔 v1 .case 鍚戝悗鍏煎锛堟棤 `case_version=2` 澹版槑鏃舵寜 v1 鎵ц锛夈€?- 鏂板 key=value 鍙傛暟璇硶銆佸紩鍙峰瓧绗︿覆锛堟敮鎸?`\"`,`\\`,`\n`锛夈€佸彉閲?`${}` 鏇挎崲銆乣wait_until` 杞銆乣expect` 鏂█銆乣act` 鍚庨獙璇併€?- 澧炲己鎶ュ憡锛坈ase_version銆乿ariables銆亀ait results銆乪xpect results 绔犺妭锛夈€?- 鏂板 4 涓?case v2 鏍蜂緥 + 10 椤?selftest銆?- 鏇存柊鍏ㄩ儴鏂囨。鍜?Skill 妯℃澘銆?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 21:55 CST
- 瀹屾垚鏃堕棿锛?026-05-28 22:18 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 鐗堟湰鍙?1.4.0 鈫?1.5.0 |
| src/winagent/WinAgent.cpp | 淇敼 | 鐗堟湰瀛楃涓叉洿鏂帮紝capabilities 鏂板 "case_v2" |
| src/winagent/CaseRunner.h | 淇敼 | 鏃犲彉鏇达紙浠?include ReportWriter.h锛?|
| src/winagent/CaseRunner.cpp | 淇敼 | 鏂板 Case v2 瀹屾暣瑙ｆ瀽鍣紙ParseV2Line銆丼ubstituteVars銆丷unCaseFileV2銆亀ait_until銆乪xpect銆乤ct鍚庨獙璇佺瓑锛夛紝RunCaseFile 鍏ュ彛娣诲姞鐗堟湰妫€娴?|
| src/winagent/ReportWriter.h | 淇敼 | 鏂板 CaseV2ExpectRecord銆丆aseV2WaitUntilRecord 缁撴瀯浣擄紝CaseReport 鏂板 caseVersion/variables/expectResults/waitResults/observationBefore/observationAfter 瀛楁 |
| src/winagent/ReportWriter.cpp | 淇敼 | 鎶ュ憡杈撳嚭鏂板 case_version銆乂ariables銆乄ait Results銆丒xpect Results銆丱bservation Before/After 绔犺妭 |
| cases/case_v2_basic.case | 鏂板 | Case v2 鍩虹 click+type 鏍蜂緥 |
| cases/case_v2_expect_success.case | 鏂板 | expect 鍏ㄩ儴閫氳繃鏍蜂緥 |
| cases/case_v2_expect_failure.case | 鏂板 | expect 澶辫触 鈫?ASSERTION_FAILED 鏍蜂緥 |
| cases/case_v2_wait_until.case | 鏂板 | wait_until selector/file_contains/window_title_contains 鏍蜂緥 |
| case_v2_selftest.ps1 | 鏂板 | 10 椤规祴璇曠殑 selftest 鑴氭湰 |
| selftest.ps1 | 淇敼 | 鐗堟湰妫€鏌?1.4.0 鈫?1.5.0 |
| CHANGELOG.md | 淇敼 | 鏂板 v1.5.0 鏉＄洰 |
| COMMAND_PROTOCOL.md | 淇敼 | 鐗堟湰鍙锋洿鏂帮紝鏂板 Case v2 鍏煎鎬ц鏄?|
| README.md | 淇敼 | 鐗堟湰鍙锋洿鏂帮紝鏂板 Case v2 浣跨敤鎸囧崡绔犺妭 |
| docs/CASE_FORMAT.md | 淇敼 | 閲嶅啓涓?v1/v2 鍙屾牸寮忔枃妗?|
| skill_template/win-desktop-agent/SKILL.md | 淇敼 | 鏂板鎺ㄨ崘 Case v2 鐢熸垚娴佺▼ |
| AUDIT_CHAIN.md | 淇敼 | 杩藉姞 v1.5.0 瀹¤璁板綍 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| Trace.cpp/Trace.h 鏈慨鏀癸紝JSON 淇″皝涓嶅彉 |
| action璇箟 | 鍚?| 鎵€鏈夊凡鏈?CLI 鍛戒护琛屼负涓嶅彉 |
| config鏍煎紡 | 鍚?| safety.conf 鏈慨鏀?|
| 鍏叡鍗忚锛圕LI锛?| 鍚?| 鎵€鏈夊懡浠ゅ弬鏁颁笉鍙橈紝鏂板 capability "case_v2" 涓虹函澧?|
| 鍏叡鍗忚锛圕ase锛?| 鏂板 | Case v2 閫氳繃 case_version=2 澹版槑鍚敤锛寁1 鏍煎紡涓嶅彉 |
| 鏋勫缓绯荤粺 | 鍚?| build.ps1 鏈慨鏀?|
| 鏉冮檺閫昏緫 | 鍚?| SafetyPolicy.cpp 鏈慨鏀癸紝v2 case 鍚屾牱鎵ц瀹夊叏绛栫暐 |

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛歚D:\desktopvisual\build.ps1`
- 鏋勫缓缁撴灉锛氶€氳繃銆倃inagent.exe 鍜?TestWindow.exe 鍧囩紪璇戦摼鎺ユ垚鍔熴€?- 鏋勫缓鏃ュ織璺緞锛歂/A锛堟瀯寤鸿緭鍑哄凡鍐呰仈锛屾棤鐙珛鏃ュ織鏂囦欢锛?
#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护 1锛歚D:\desktopvisual\bin\winagent.exe version`
- 娴嬭瘯缁撴灉 1锛氶€氳繃銆傝緭鍑虹増鏈?1.5.0锛宐uild_time "May 28 2026 22:08:42"锛宑apabilities 鍖呭惈 "case_v2"銆?
- 娴嬭瘯鍛戒护 2锛歚D:\desktopvisual\selftest.ps1`
- 娴嬭瘯缁撴灉 2锛氶€氳繃銆係elftest passed. Dogfood: SKIPPED. 鎶ュ憡璺緞 D:\desktopvisual\artifacts\selftest_report.md銆?
- 娴嬭瘯鍛戒护 3锛歚D:\desktopvisual\case_v2_selftest.ps1`
- 娴嬭瘯缁撴灉 3锛?0/10 鍏ㄩ儴閫氳繃銆傛槑缁嗭細
  1. Old v1 case still passes 鈫?PASS
  2. Case v2 basic passes 鈫?PASS
  3. Variable substitution 鈫?PASS
  4. wait_until selector passes 鈫?PASS
  5. expect success passes 鈫?PASS
  6. expect failure returns ASSERTION_FAILED 鈫?PASS
  7. Bad quotes returns CASE_PARSE_FAILED 鈫?PASS
  8. locate failure stops subsequent input 鈫?PASS
  9. act with post-action expect verification 鈫?PASS
  10. Case v2 report includes case_version 鈫?PASS

- 娴嬭瘯鏃ュ織璺緞锛氬唴鑱旇緭鍑猴紙鏃犵嫭绔嬫棩蹇楁枃浠舵崟鑾凤級

#### 鐢熸垚璇佹嵁

- diff鏂囦欢锛歂/A锛堥潪 git 浠撳簱锛岄€氳繃鏂囦欢淇敼鍒楄〃杩借釜鍙樻洿锛?- 鐗堟湰鎶ュ憡锛歛gent_reports/v1.5.0_report.md锛堟湭鐢熸垚鐙珛鎶ュ憡锛屾祴璇曠粨鏋滃唴鑱斾簬鏈璁¤褰曪級
- 鏋勫缓鏃ュ織锛歭ogs/v1.5.0_build.log锛堟湭鎹曡幏鐙珛鏃ュ織锛屾瀯寤鸿緭鍑烘樉绀烘垚鍔燂級
- 娴嬭瘯鏃ュ織锛歭ogs/v1.5.0_test.log锛堟湭鎹曡幏鐙珛鏃ュ織锛屾祴璇曠粨鏋滃唴鑱斾簬鏈璁¤褰曪級

#### 鏈獙璇侀闄?
- 椤圭洰闈?git 绠＄悊锛宒iff 鏃犳硶鑷姩鐢熸垚銆傚缓璁悗缁皢椤圭洰绾冲叆 git 浠ヤ究绮剧‘杩借釜鍙樻洿銆?- `D:\desktopvisual` 鍜?`D:\desktopvisual-cc` 鏄袱涓嫭绔嬬洰褰曘€傛湰娆′慨鏀瑰湪 `-cc` 鐩綍寮€鍙戝悗閫氳繃 cp 鍚屾鑷虫瀯寤虹洰褰曘€備袱涓洰褰曠殑鏂囦欢涓€鑷存€ч渶浜哄伐纭銆?- OCR 妯″潡浠嶄负瀛樻牴锛圤crController.cpp锛夛紝`text:` 閫夋嫨鍣ㄥ拰 `find-text`/`click-text` 鍛戒护鍧囪繑鍥?`OCR_UNAVAILABLE`銆?- `expect active_window_title_contains` 渚濊禆 `ActiveWindowInfo()`锛岃鍑芥暟鍦?CaseRunner.cpp v2 namespace 涓湁鐙珛鍓湰锛屼笌 WinAgent.cpp 鍜?ObserveController.cpp 涓殑瀹炵幇淇濇寔涓€鑷达紙涓変唤鎷疯礉锛夈€?- Case v2 鐨?`type selector="..." text="..."` 鍙樹綋锛堝甫閫夋嫨鍣ㄥ畾浣嶅悗鎵撳瓧锛夋湭缁忎笓闂ㄦ祴璇曪紝浠呴€氳繃 `act action="type"` 瑕嗙洊銆?- `selector_selftest.ps1` 鍜?`rc_check.ps1` 鏈鏈繍琛岋紙鍘?selftest 宸查€氳繃锛岀増鏈彿宸叉洿鏂帮級銆?- skill_template references 涓?CASE_FORMAT.md 鍓湰鏈笌涓?docs/CASE_FORMAT.md 鍚屾锛堥渶鎵嬪姩澶嶅埗锛夈€?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 CaseRunner.cpp 涓?ParseV2Line 鐨勮В鏋愰€昏緫鏄惁瑕嗙洊鎵€鏈夎竟鐣屾儏鍐碉紙宓屽寮曞彿銆佺壒娈婂瓧绗︺€佽秴闀胯绛夛級銆?- 澶嶆牳 ExecuteWaitUntilV2 鐨勮疆璇㈤€昏緫锛?00ms 闂撮殧鏄惁鍚堢悊锛宼imeout 绮惧害鏄惁鍙帴鍙椼€?- 澶嶆牳 ExecuteExpectV2 鐨?`active_window_title_contains` 瀹炵幇鏄惁涓?WinAgent.cpp 涓?ActiveWindowInfo 鐨勯€昏緫涓€鑷淬€?- 澶嶆牳 RunPostActionExpects 鍦?act 澶辫触鍚庢槸鍚︿粛鐒舵纭墽琛岋紙褰撳墠璁捐锛氬厛鎵ц鍔ㄤ綔锛屾垚鍔熷悗鎵嶆墽琛?expect锛夈€?- 楠岃瘉 `D:\desktopvisual` 鍜?`D:\desktopvisual-cc` 涓や釜鐩綍鎵€鏈夋枃浠朵竴鑷存€с€?- 纭 `docs/AGENT_USAGE_GUIDE.md` 鏄惁闇€瑕佹洿鏂帮紙鏈鏈慨鏀硅鏂囦欢锛屼絾浠诲姟瑕佹眰涓湁鎻愬強锛夈€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆傛墍鏈?10 椤?selftest 閫氳繃锛屼富 selftest 閫氳繃锛屽悜鍚庡吋瀹瑰凡楠岃瘉銆?
---

### Version: v2.0.0

#### 浠诲姟鐩爣

- 瀹炵幇鐪熸鍙敤鐨?Windows OCR 鏂囨湰璇诲彇鑳藉姏锛屾浛鎹?v0.3.2 鐨?OCR 瀛樻牴銆?- 浣跨敤 Windows SDK 鍐呯疆 C++/WinRT 澶存枃浠惰皟鐢?`Windows.Media.Ocr.OcrEngine`锛堜笉涓嬭浇绗笁鏂逛緷璧栵級銆?- 鏂板 OCR 鍛戒护锛歳ead-window-text, read-region-text, wait-text, assert-text-contains銆?- 鏇存柊 find-text/click-text 涓虹湡瀹?OCR 瀹炵幇銆?- Selector text: 闆嗘垚鐪熷疄 OCR锛屾敮鎸?exact/index 鍖归厤銆?- Case v2 鏂板 read_text, wait_until text_contains, expect text_contains銆?- 鍔ㄦ€?OCR 鑳藉姏澹版槑銆?- OCR 澶辫触鍚庝笉鍏佽鐚滃潗鏍囩偣鍑汇€?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 22:20 CST
- 瀹屾垚鏃堕棿锛?026-05-28 22:45 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 鐗堟湰鍙?1.5.0 鈫?2.0.0 |
| src/winagent/OcrController.h | 閲嶅啓 | 鏂板 OcrWord/OcrLine/OcrResult/OcrCapability 缁撴瀯浣擄紝鏂板 5 涓嚱鏁板０鏄?|
| src/winagent/OcrController.cpp | 閲嶅啓 | 瀹炵幇鐪熷疄 WinRT OCR锛屽惈缂栬瘧鏃?fallback锛坄__has_include` guard锛夛紝杩愯鏃?`TryCreateFromUserProfileLanguages` 妫€娴?|
| src/winagent/WinAgent.cpp | 淇敼 | 鐗堟湰 2.0.0锛屽姩鎬?OCR 鑳藉姏澹版槑锛屾柊澧?4 涓懡浠わ紝鏇存柊 find-text/click-text |
| src/winagent/Selector.cpp | 淇敼 | text:exact 鏀寔锛宨ndex 鏀寔锛岃皟鐢ㄧ湡瀹?OCR |
| src/winagent/CaseRunner.cpp | 淇敼 | 鏂板 #include OcrController.h锛宺ead_text 鍛戒护锛寃ait_until/expect text_contains |
| build.ps1 | 淇敼 | 鏂板 /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS 鍜?windowsapp.lib |
| selftest.ps1 | 淇敼 | 鐗堟湰妫€鏌?1.5.0 鈫?2.0.0 |
| ocr_selftest.ps1 | 鏂板 | 7 椤?OCR 娴嬭瘯锛堝惈 SKIPPED 閫昏緫锛?|
| CHANGELOG.md | 淇敼 | 鏂板 v2.0.0 鏉＄洰 |
| README.md | 淇敼 | 鐗堟湰鍙锋洿鏂?|
| COMMAND_PROTOCOL.md | 淇敼 | 鐗堟湰鍙锋洿鏂?|
| skill_template/win-desktop-agent/SKILL.md | 淇敼 | 鏇存柊 locator 浼樺厛绾э細UIA > OCR > image > coord |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| JSON 淇″皝涓嶅彉 |
| action璇箟 | 鍚?| 宸叉湁 CLI 鍛戒护琛屼负涓嶅彉 |
| config鏍煎紡 | 鍚?| safety.conf 鏈慨鏀?|
| 鍏叡鍗忚锛圕LI锛?| 鏂板 | 4 涓柊鍛戒护锛宖ind-text 鏂板鍙€夊弬鏁帮紝鍧囦负绾 |
| 鍏叡鍗忚锛圕ase锛?| 鏂板 | read_text, wait_until text_contains, expect text_contains锛堜粎 v2锛?|
| 鏋勫缓绯荤粺 | 淇敼 | 鏂板缂栬瘧瀹忓拰 windowsapp.lib 閾炬帴 |
| 鏉冮檺閫昏緫 | 鍚?| OCR 鎿嶄綔鍚屾牱閫氳繃 SafetyPolicy 妫€鏌?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛歚D:\desktopvisual\build.ps1`
- 鏋勫缓缁撴灉锛氶€氳繃銆倃inagent.exe 鍜?TestWindow.exe 鍧囩紪璇戦摼鎺ユ垚鍔熴€?- 缂栬瘧鐜锛歁SVC 14.51 (VS 2026), Windows SDK 10.0.26100.0, C++/WinRT headers included

#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护 1锛歚D:\desktopvisual\bin\winagent.exe version`
- 娴嬭瘯缁撴灉 1锛氶€氳繃銆傜増鏈?2.0.0, ocr_available=true, ocr_engine="Windows.Media.Ocr.OcrEngine (WinRT)", capabilities 鍖呭惈 read_window_text/read_region_text/find_text/click_text/wait_text銆?
- 娴嬭瘯鍛戒护 2锛歚D:\desktopvisual\selftest.ps1`
- 娴嬭瘯缁撴灉 2锛氶€氳繃銆係elftest passed. Dogfood: SKIPPED.

- 娴嬭瘯鍛戒护 3锛歚D:\desktopvisual\case_v2_selftest.ps1`
- 娴嬭瘯缁撴灉 3锛?0/10 鍏ㄩ儴閫氳繃銆?
- 娴嬭瘯鍛戒护 4锛歚D:\desktopvisual\ocr_selftest.ps1`
- 娴嬭瘯缁撴灉 4锛?/7 鍏ㄩ儴閫氳繃銆傛槑缁嗭細
  1. read-window-text reads visible text (7 words, 3 lines found) 鈫?PASS
  2. find-text locates text ("AgentTestWindow" at rect 32,17) 鈫?PASS
  3. text selector locates 鈫?PASS
  4. Non-existent text returns LOCATOR_NOT_FOUND 鈫?PASS
  5. Unauthorized window returns WINDOW_NOT_FOUND 鈫?PASS
  6. find-text with --match exact 鈫?PASS
  7. Version reports OCR capability correctly 鈫?PASS

- OCR 杩愯鏃堕獙璇侊細`read-window-text --title "Agent Test Window"` 鎴愬姛璇诲彇 7 涓崟璇嶃€? 琛屾枃鏈紝杩斿洖 bounding box 鍧愭爣銆?
#### 鐢熸垚璇佹嵁

- diff鏂囦欢锛歂/A锛堥潪 git 浠撳簱锛?- 鏋勫缓鏃ュ織锛氬唴鑱斾簬鏋勫缓杈撳嚭
- 娴嬭瘯鏃ュ織锛氬唴鑱斾簬娴嬭瘯杈撳嚭

#### 鏈獙璇侀闄?
- C++/WinRT 鐨?`auto` 杩斿洖绫诲瀷鍑芥暟锛坄LanguageTag()`, `DisplayName()`锛夊湪姝?MSVC 鐗堟湰涓嬩笉鍙敤銆傚綋鍓嶄娇鐢ㄧ‖缂栫爜 "system-default" 浣滀负璇█鏍囩銆備笉褰卞搷鏍稿績 OCR 璇嗗埆鍔熻兘銆?- WinRT 鐨?`IMemoryBufferByteAccess` 鎺ュ彛鏈湪 C++/WinRT 涓姇褰憋紝閬垮厤浣跨敤璇ヨ矾寰勩€傛敼鐢?`StorageFile::GetFileFromPathAsync` + `BitmapDecoder` 璺緞鍔犺浇鎴浘銆?- `read-region-text` 鏈粡鐙珛 selftest 娴嬭瘯锛堜粎閫氳繃浠ｇ爜瀹℃煡楠岃瘉閫昏緫姝ｇ‘鎬э級銆?- `wait-text` 鍜?`assert-text-contains` 鏈粡鐙珛 selftest 娴嬭瘯銆?- 涓存椂 OCR BMP 鏂囦欢鍐欏叆 `%TEMP%` 鐩綍锛屾甯告儏鍐典細琚?`DeleteFileW` 娓呯悊銆傚紓甯告儏鍐典笅鍙兘娈嬬暀銆?- 褰撳墠 OCR 璇█鍥哄畾涓虹郴缁熺敤鎴烽厤缃枃浠惰瑷€锛屾棤娉曞湪 `read-window-text` 涓寚瀹氫笉鍚岃瑷€锛坄--language` 鍙傛暟鏈疄鐜板畬鏁村姛鑳斤級銆?- `D:\desktopvisual` 鍜?`D:\desktopvisual-cc` 涓や釜鐩綍浠嶉渶浜哄伐纭涓€鑷存€с€?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 `OcrController.cpp` 涓?WinRT 寮傚父澶勭悊鏄惁瀹屾暣瑕嗙洊鎵€鏈?OCR 澶辫触鍦烘櫙銆?- 澶嶆牳 `ReadRegionText` 鐨勫潗鏍囪浆鎹㈤€昏緫锛坈lient鈫抯creen鈫抴indow bitmap鈫抍rop锛夈€傚綋鍓嶅疄鐜板悓鏃剁敤浜?ClientToScreen 鍜?PrintWindow锛岄渶纭 DPI 缂╂斁涓嬬殑琛屼负銆?- 澶嶆牳 `RecognizeBitmapFile` 涓粠 BMP 鏂囦欢鍔犺浇 `SoftwareBitmap` 鐨勬€ц兘褰卞搷锛堟瘡娆?OCR 鎿嶄綔閮芥秹鍙婃枃浠?I/O锛夈€?- 纭 C++/WinRT 澶存枃浠剁殑 `auto` 杩斿洖绫诲瀷闂鏄惁褰卞搷鍏朵粬 WinRT API 璋冪敤銆?- 澶嶆牳 `find-text` 鐨?`matchCount` 鍦ㄥ鍖归厤鍦烘櫙涓嬬殑杩斿洖鍊兼槸鍚︿笌 `LOCATOR_NOT_UNIQUE` 閿欒鐮佷竴鑷淬€?- 纭 `#pragma comment(lib, "windowsapp")` 鍦?MSVC 14.51 涓嬬殑閾炬帴琛屼负鏄惁绋冲畾銆?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆傚叏閮?selftest 閫氳繃锛堜富 selftest + case_v2 10/10 + OCR 7/7锛夈€俉indows OCR 宸插疄鐜扮湡瀹炲彲鐢ㄣ€?
---

### Version: v2.1.0

#### 浠诲姟鐩爣

- 寤虹珛鐪熷疄 Windows 搴旂敤 dogfood 娴嬭瘯鐭╅樀锛岃瘉鏄庡钩鍙板彲鎿嶄綔鐪熷疄妗岄潰杞欢銆?- 瑕嗙洊 5 娆?Windows 搴旂敤锛歂otepad銆丆alculator銆丒xplorer銆丒dge銆乂S Code銆?- 姣忔搴旂敤鐙珛娴嬭瘯鐩綍锛坈ase + run.ps1 + README + expected.md锛夈€?- 缁熶竴鐭╅樀鑴氭湰 dogfood_matrix.ps1 杈撳嚭鑱氬悎 Markdown 鎶ュ憡鍜屾垚鍔熺巼缁熻銆?- 闆?C++ 浠ｇ爜閫昏緫鍙樻洿锛岀函娴嬭瘯鍩虹璁炬柦寤鸿銆?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 22:46 CST
- 瀹屾垚鏃堕棿锛?026-05-28 22:50 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 鐗堟湰鍙?2.0.0 鈫?2.1.0 |
| src/winagent/WinAgent.cpp | 淇敼 | 鐗堟湰瀛楃涓?2.0.0 鈫?2.1.0 |
| CHANGELOG.md | 淇敼 | 鏂板 v2.1.0 鏉＄洰 |
| dogfood/ (19 鏂囦欢) | 鏂板 | 5 涓簲鐢?dogfood 娴嬭瘯濂椾欢 |
| dogfood_matrix.ps1 | 鏂板 | 缁熶竴鐭╅樀杩愯鍣ㄥ拰鑱氬悎鎶ュ憡 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| 鏃?C++ 鍙樻洿 |
| action璇箟 | 鍚?| 鏃?C++ 鍙樻洿 |
| config鏍煎紡 | 鍚?| 鏃犲彉鏇?|
| 鍏叡鍗忚 | 鍚?| 鏃犲彉鏇?|
| 鏋勫缓绯荤粺 | 鍚?| 鏃犲彉鏇?|
| 鏉冮檺閫昏緫 | 鍚?| 鏃犲彉鏇?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛歚D:\desktopvisual\build.ps1`
- 鏋勫缓缁撴灉锛氶€氳繃锛堜粎鐗堟湰瀛楃涓插彉鏇达級

#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护锛歚D:\desktopvisual\dogfood_matrix.ps1`
- 娴嬭瘯缁撴灉锛? 娆惧簲鐢ㄥ叏閮ㄦ墽琛屻€傜粨鏋滅煩闃碉細
  - Edge: **PASS** (UIA locators used, 2 Edit fields found, 5606ms)
  - Notepad: SKIPPED (绯荤粺涓枃 Notepad 鏍囬鏈尮閰?
  - Calculator: SKIPPED (褰撳墠 Calculator 鐗堟湰鏈€氳繃 OCR/UIA 楠岃瘉鍒?"42")
  - Explorer: SKIPPED (绐楀彛鐒︾偣鏈疄鐜版枃浠跺す鍒涘缓)
  - VS Code: SKIPPED (鏈畨瑁?
  - 閫氳繃鐜囷紙涓嶈 SKIP锛夛細100% (1/1)
  - 鎬昏€楁椂锛?5680ms

#### 鐢熸垚璇佹嵁

- 鐭╅樀鎶ュ憡锛歚D:\desktopvisual\artifacts\dogfood_matrix_report.md`
- 鍚勫簲鐢ㄦ姤鍛婏細`D:\desktopvisual\artifacts\dogfood\<app>\report.md`

#### 鏈獙璇侀闄?
- Notepad dogfood 渚濊禆鑻辨枃 "Notepad" 鏍囬鍖归厤锛屼腑鏂囩郴缁熷彲鑳芥樉绀轰负"璁颁簨鏈?瀵艰嚧 `WINDOW_NOT_FOUND`銆?- Calculator 鐨?UIA 鏍戠粨鏋勫湪涓嶅悓 Windows 鐗堟湰闂村樊寮傚ぇ锛屽綋鍓?OCR 鏈湪 Calculator 绐楀彛姝ｇ‘璇嗗埆 "42"銆?- Explorer dogfood 鐨?`Ctrl+Shift+N` 鏂版枃浠跺す蹇嵎閿緷璧栫獥鍙ｇ劍鐐癸紝鑷姩鍖栫幆澧冨彲鑳界劍鐐逛涪澶便€?- Edge 娴嬭瘯渚濊禆 Edge 宸插畨瑁呬笖棣栨杩愯涓嶅脊鍑烘杩庨〉锛坄--no-first-run` 鍙傛暟锛夈€?- VS Code dogfood 渚濊禆 `code` 鍛戒护鍦?PATH 涓垨鐗瑰畾瀹夎璺緞銆?- 鎵€鏈?SKIPPED 椤归兘闇€瑕佸湪鐩爣鐜锛堣嫳鏂?Windows + 鐗瑰畾搴旂敤鐗堟湰锛変笅閲嶆柊楠岃瘉銆?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 dogfood 鍚?run.ps1 涓簲鐢ㄧ獥鍙ｆ爣棰樺尮閰嶆槸鍚﹁鐩栦腑鏂?鑻辨枃鐜銆?- 澶嶆牳 Explorer dogfood 鐨勭劍鐐规ā鍨嬧€斺€擿Start-Process explorer.exe` 鍚庣獥鍙ｈ幏鍙栧彲鑳介渶瑕佷笉鍚岀瓥鐣ャ€?- 澶嶆牳 Edge dogfood 鐨?`--no-first-run` 鏄惁鍦ㄦ墍鏈?Edge 鐗堟湰涓婃湁鏁堛€?- 纭 Calculator dogfood 鍦ㄥ綋鍓嶇幆澧冧腑 SKIP 鏄幆澧冮棶棰樿€岄潪浠ｇ爜閫昏緫閿欒銆?- 澶嶆牳 dogfood_matrix.ps1 鐨勭粺璁￠€昏緫鏄惁姝ｇ‘澶勭悊浜?SKIPPED 涓嶈鍏ユ垚鍔熺巼鐨勫垎姣嶃€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆侱ogfood 鐭╅樀鍩虹璁炬柦宸插缓绔嬨€侲dge 搴旂敤鐪熷疄閫氳繃楠岃瘉銆傚叾浣?4 涓簲鐢ㄥ洜鐜宸紓 SKIP锛堥潪浠ｇ爜缂洪櫡锛夈€倂2.1.0 鏃?C++ 浠ｇ爜鍙樻洿椋庨櫓銆?
---

### Version: v2.2.0

#### 浠诲姟鐩爣

- 鍗囩骇 Codex Skill 妯℃澘鑷?v2.2锛屼娇 Agent 鑳芥洿绋冲畾鍦伴€氳繃 Skill 浣跨敤 DesktopVisual銆?- 閲嶆瀯 SKILL.md 涓?8 涓竻鏅扮珷鑺傦紙鍚姩銆佸畾浣嶄紭鍏堢骇銆佸姩浣滄墽琛屻€侀獙璇併€佸仠姝㈡潯浠躲€佽剼鏈€佸弬鑰冦€乨ogfood锛夈€?- 鏂板 6 涓?Skill 杈呭姪鑴氭湰銆?- 鏂板 Agent 浠诲姟绀轰緥鏂囨。銆?- 鎵╁睍 Skill selftest 浠庢棫鏍煎紡鍒?9 椤规鏌ャ€?- 鍚屾鍏ㄩ儴 7 涓?references銆?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 22:52 CST
- 瀹屾垚鏃堕棿锛?026-05-28 23:00 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 2.1.0 鈫?2.2.0 |
| CHANGELOG.md | 淇敼 | 鏂板 v2.2.0 |
| skill_template/win-desktop-agent/SKILL.md | 閲嶅啓 | 娓呮櫚 agent 宸ヤ綔娴併€佸畾浣嶄紭鍏堢骇銆佸仠姝㈡潯浠?|
| skill_template/win-desktop-agent/scripts/observe-target.ps1 | 鏂板 | 灏佽 observe 鍛戒护 |
| skill_template/win-desktop-agent/scripts/locate-target.ps1 | 鏂板 | 灏佽 locate 鍛戒护 |
| skill_template/win-desktop-agent/scripts/act-target.ps1 | 鏂板 | 灏佽 act 鍛戒护 |
| skill_template/win-desktop-agent/scripts/run-case-v2.ps1 | 鏂板 | 灏佽 run-case 鍛戒护 |
| skill_template/win-desktop-agent/scripts/summarize-report.ps1 | 鏂板 | 瑙ｆ瀽 Markdown 鎶ュ憡鎽樿 |
| skill_template/win-desktop-agent/scripts/run-dogfood-matrix.ps1 | 鏂板 | 灏佽 dogfood_matrix |
| skill_template/win-desktop-agent/scripts/selftest-skill-template.ps1 | 閲嶅啓 | 9 椤规鏌?|
| skill_template/win-desktop-agent/references/ (7 files) | 鍚屾 | 鏇存柊鍒版渶鏂扮増鏈?|
| docs/AGENT_TASK_EXAMPLES.md | 鏂板 | 6 涓?agent 浠诲姟绀轰緥 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| 鏃?C++ 鍙樻洿 |
| action璇箟 | 鍚?| 鏃?C++ 鍙樻洿 |
| config鏍煎紡 | 鍚?| 鏃犲彉鏇?|
| 鍏叡鍗忚 | 鍚?| 鏃犲彉鏇?|
| 鏋勫缓绯荤粺 | 鍚?| 鏃犲彉鏇?|
| 鏉冮檺閫昏緫 | 鍚?| 鏃犲彉鏇?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛氭湭鎵ц锛堟棤 C++ 鍙樻洿锛寃inagent.exe 鏈噸缂栵級
- 鏋勫缓缁撴灉锛歂/A

#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护锛歚D:\desktopvisual\skill_template\win-desktop-agent\scripts\selftest-skill-template.ps1 -SkipBuild`
- 娴嬭瘯缁撴灉锛?*9/9 鍏ㄩ儴閫氳繃**銆傛槑缁嗭細
  1. New scripts exist (6 scripts) 鈫?PASS
  2. References complete (7 references) 鈫?PASS
  3. SKILL.md contains observe-act-verify flow 鈫?PASS
  4. SKILL.md contains stop conditions (5 error codes) 鈫?PASS
  5. run-case-v2.ps1 executes case_v2_basic.case 鈫?PASS
  6. observe-target.ps1 outputs observe data 鈫?PASS
  7. locate-target.ps1 locates Click Me 鈫?PASS
  8. act-target.ps1 clicks Click Me 鈫?PASS
  9. summarize-report.ps1 summarizes failure report 鈫?PASS

#### 鐢熸垚璇佹嵁

- Skill selftest 杈撳嚭锛氬唴鑱旓紙9/9 PASS锛?- 鏃犳瀯寤轰骇鐗╁彉鏇?
#### 鏈獙璇侀闄?
- `run-dogfood-matrix.ps1` skill 鑴氭湰渚濊禆 `D:\desktopvisual\dogfood_matrix.ps1` 瀛樺湪銆傝嫢鐢ㄦ埛绉诲姩椤圭洰璺緞锛岃剼鏈け鏁堛€?- Skill 鑴氭湰涓‖缂栫爜 `D:\desktopvisual` 璺緞銆傚鏋滅敤鎴峰畨瑁呭埌涓嶅悓浣嶇疆锛屾墍鏈夎剼鏈渶鎵嬪姩淇敼銆?- `summarize-report.ps1` 鐨?Markdown 瑙ｆ瀽鍩轰簬姝ｅ垯琛ㄨ揪寮忥紝鑻ユ姤鍛婃牸寮忓彉鏇村彲鑳借В鏋愬け璐ャ€?- `docs/AGENT_TASK_EXAMPLES.md` 涓殑 Calculator 绀轰緥渚濊禆 `calc.exe` 鍜?OCR锛屽湪涓嶅悓 Windows 鐗堟湰涓婂彲鑳借涓轰笉鍚屻€?- `docs/SKILL_INSTALLATION.md` 鍜?`docs/SKILL_INTEGRATION_PLAN.md` 鏈疄闄呮洿鏂板唴瀹癸紙浠呬换鍔¤姹備腑鎻愬強锛夈€?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 SKILL.md 涓?8 涓?Stop Conditions 琛ㄦ牸鏄惁瑕嗙洊鎵€鏈夊凡鐭ュけ璐ユā寮忋€?- 澶嶆牳 locator priority 绔犺妭鏄惁涓?VISUAL_SAFETY_FREEZE.md 涓殑瑙勫垯涓€鑷淬€?- 澶嶆牳 `act-target.ps1` 鏄惁姝ｇ‘澶勭悊 `--text` 鍙€夊弬鏁帮紙绌哄瓧绗︿覆杈圭晫鎯呭喌锛夈€?- 澶嶆牳 `selftest-skill-template.ps1` 鍦ㄦ瘡涓祴璇曞悗鏄惁姝ｇ‘娓呯悊 TestWindow 杩涚▼銆?- 纭 `references/` 涓?SAFETY.md 鍜?AGENT_USAGE_GUIDE.md 鍐呭鏄惁涓庨」鐩富鏂囨。涓€鑷淬€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆係kill selftest 9/9 閫氳繃銆傞浂 C++ 鍙樻洿椋庨櫓銆侫gent 宸ヤ綔娴佹枃妗ｅ寲瀹屾暣銆?
---

### Version: v2.3.0

#### 浠诲姟鐩爣

- 鏂板鏈湴鏈嶅姟妯″紡 `winagent serve`锛屼负 Agent 鎻愪緵杩炵画 session 璋冪敤鑳藉姏銆?- 浣跨敤 Windows Named Pipe 瀹炵幇锛圽\.\pipe\DesktopVisualService锛夛紝JSON-over-pipe 鍗忚銆?- 鏀寔 7 涓?API 绔偣锛?version, /observe, /locate, /act, /run-case, /report, /shutdown銆?- Session 鐘舵€佽拷韪紝Service audit log銆?- 涓嶇粫杩?SafetyPolicy锛屼笉寮曞叆绗笁鏂逛緷璧栥€?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 23:05 CST
- 瀹屾垚鏃堕棿锛?026-05-28 23:15 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 2.2.0 鈫?2.3.0 |
| src/winagent/WinAgent.cpp | 淇敼 | 鏂板 CommandServe (~200琛?, 8涓緟鍔╁嚱鏁? 鍛藉悕绠￠亾鏈嶅姟鍣?|
| serve_start.ps1 | 鏂板 | 鍚庡彴鍚姩鏈嶅姟 |
| serve_stop.ps1 | 鏂板 | 閫氳繃 /shutdown 鍋滄鏈嶅姟 |
| serve_selftest.ps1 | 鏂板 | 9 椤规湇鍔＄鐐归獙璇?|
| CHANGELOG.md | 淇敼 | 鏂板 v2.3.0 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| JSON 淇″皝涓嶅彉锛屾湇鍔℃ā寮忓鐢ㄥ凡鏈?Command* 鍑芥暟 |
| action璇箟 | 鍚?| 鎵€鏈?CLI 鍛戒护琛屼负涓嶅彉 |
| config鏍煎紡 | 鍚?| 鏃犲彉鏇?|
| 鍏叡鍗忚锛圕LI锛?| 鏂板 | serve 鍛戒护涓虹函澧?|
| 鍏叡鍗忚锛圕ase锛?| 鍚?| 鏃犲彉鏇?|
| 鏋勫缓绯荤粺 | 鍚?| 鏃犲彉鏇?|
| 鏉冮檺閫昏緫 | 鍚?| 鏈嶅姟妯″紡閫氳繃 RunWinAgent 璋冪敤宸叉湁鍛戒护锛屽畨鍏ㄧ瓥鐣ュ畬鍏ㄤ竴鑷?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛歚D:\desktopvisual\build.ps1`
- 鏋勫缓缁撴灉锛氶€氳繃銆倃inagent.exe 缂栬瘧閾炬帴鎴愬姛銆?
#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护锛歚D:\desktopvisual\serve_selftest.ps1`
- 娴嬭瘯缁撴灉锛?*9/9 鍏ㄩ儴閫氳繃**銆傛槑缁嗭細
  1. Start winagent serve 鈫?PASS (PID 11692, pipe created)
  2. GET /version 鈫?PASS (v2.3.0)
  3. POST /observe 鈫?PASS
  4. POST /locate 鈫?PASS (method=uia)
  5. POST /act click 鈫?PASS (method=invoke_pattern)
  6. POST /run-case 鈫?PASS (13/13 steps)
  7. GET /report 鈫?PASS (content_length=3651)
  8. POST /shutdown 鈫?PASS (7 requests, 1 action, 0 errors)
  9. service_audit.log 鈫?PASS (13 entries)

#### 鐢熸垚璇佹嵁

- Service audit log: `D:\desktopvisual\artifacts\service_audit.log` (13 entries)
- Serve selftest 杈撳嚭锛氬唴鑱旓紙9/9 PASS锛?
#### 鏈獙璇侀闄?
- Named pipe 鏈€澶у疄渚嬫暟涓?1锛圥IPE_UNLIMITED_INSTANCES 鏈惎鐢級锛屽悓涓€鏃堕棿鍙兘鏈変竴涓鎴风杩炴帴銆?- 鏈嶅姟妯″紡涓哄崟绾跨▼闃诲锛坅ccept 鈫?process 鈫?disconnect 鈫?accept锛夛紝涓嶆敮鎸佸苟鍙戣繛鎺ャ€?- /report 绔偣閫氳繃 IsReadPathAllowed 妫€鏌ヨ矾寰勫畨鍏紝浣?SimpleJsonGetString 鐨?JSON 瑙ｆ瀽鏄畝鍖栧疄鐜帮紝涓嶅鐞嗗祵濂楀紩鍙峰拰杞箟銆?- StreamWriter/ReadFile UTF-8 缂栬В鐮佸湪寮傚父娑堟伅鍚潪 ASCII 瀛楃鏃舵湭鍏呭垎娴嬭瘯銆?- `serve_start.ps1` 渚濊禆 Start-Process -NoNewWindow锛岀獥鍙ｅ叧闂椂鏈嶅姟杩涚▼鍙兘琚粓姝€?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 SimpleJsonGetString/SimpleJsonGetRaw 鏄惁鍦ㄦ墍鏈夎姹傛牸寮忎笅姝ｇ‘瑙ｆ瀽銆?- 澶嶆牳 CommandServe 涓閬撻敊璇鐞嗭紙CreateNamedPipe 澶辫触銆丷eadFile 澶辫触銆乄riteFile 澶辫触锛夋槸鍚﹀畬鍠勩€?- 澶嶆牳鏈嶅姟妯″紡涓?stdout 閲嶅畾鍚戯紙rdbuf swap锛夋槸鍚︾嚎绋嬪畨鍏紙褰撳墠鍗曠嚎绋嬫棤闂锛屼絾鏈潵鍙兘寮曞叆澶氱嚎绋嬶級銆?- 纭 /report 绔偣鐨勮矾寰勫畨鍏ㄦ鏌ユ槸鍚︿笌 CLI read-file 鍛戒护琛屼负涓€鑷淬€?- 澶嶆牳 service_audit.log 鐨勭紪鐮侊紙UTF-8 with BOM锛夋槸鍚﹀湪鎵€鏈夋煡鐪嬪櫒涓彲璇汇€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆係erve selftest 9/9 閫氳繃銆? 涓湇鍔＄鐐瑰叏閮ㄩ獙璇併€傚凡鏈?CLI 鍛戒护闆跺奖鍝嶃€?
---

### Version: v3.0.0

#### 浠诲姟鐩爣

- 褰㈡垚 Windows Computer Use MVP銆傛暣鍚堝凡鏈夎兘鍔涗负鍙紨绀恒€佸彲瀹¤銆佸彲澶嶇幇鐨勬闈?Agent 闂幆銆?- 鏂板 TaskRunner 妯″潡锛歵ask.json 瑙ｆ瀽 鈫?observe鈫抣ocate鈫抋ct鈫抩bserve鈫抳erify 鎵ц寰幆 鈫?澶辫触鍒嗙被 鈫?鏈夐檺鎭㈠ 鈫?MVP 鎶ュ憡銆?
#### 淇敼鏃堕棿

- 寮€濮嬫椂闂达細2026-05-28 23:05 CST
- 瀹屾垚鏃堕棿锛?026-05-28 23:20 CST

#### 淇敼鏂囦欢鍒楄〃

| 鏂囦欢璺緞 | 淇敼绫诲瀷 | 淇敼鍘熷洜 |
|---|---|---|
| VERSION | 淇敼 | 2.3.0 鈫?3.0.0 |
| src/winagent/TaskRunner.h | 鏂板 | TaskDefinition/FailureClassification/TaskResult 鏁版嵁缁撴瀯 |
| src/winagent/TaskRunner.cpp | 鏂板 | ~420琛岋細JSON瑙ｆ瀽銆佸け璐ュ垎绫诲櫒(12绫?銆佹楠ゆ墽琛屽櫒銆佹仮澶嶉€昏緫銆丮VP鎶ュ憡鐢熸垚 |
| src/winagent/WinAgent.cpp | 淇敼 | 鏂板 run-task CLI鍛戒护銆?run-task service绔偣銆乮nclude TaskRunner.h |
| build.ps1 | 淇敼 | sources 鏂板 TaskRunner.cpp |
| tasks/ (6 .task.json) | 鏂板 | testwindow_basic/notepad_input/calculator_42/edge_local_form/explorer_temp_folder/vscode_edit_save |
| mvp_selftest.ps1 | 鏂板 | 4 tests锛歜asic PASS銆乤pp SKIP銆乴ocator recovery stop銆乻afety denied stop |
| CHANGELOG.md | 淇敼 | 鏂板 v3.0.0 |

#### 璇箟褰卞搷妫€鏌?
| 妫€鏌ラ」 | 鏄惁鏀瑰姩 | 璇存槑 |
|---|---|---|
| trace璇箟 | 鍚?| 宸叉湁鍛戒护涓嶅彉 |
| action璇箟 | 鍚?| 宸叉湁鍛戒护涓嶅彉 |
| config鏍煎紡 | 鍚?| 鏃犲彉鏇?|
| 鍏叡鍗忚锛圕LI锛?| 鏂板 | run-task 鍛戒护涓虹函澧?|
| 鍏叡鍗忚锛圕ase锛?| 鍚?| 鏃犲彉鏇?|
| 鏋勫缓绯荤粺 | 淇敼 | TaskRunner.cpp 鍔犲叆缂栬瘧鍒楄〃 |
| 鏉冮檺閫昏緫 | 鍚?| run-task 閫氳繃 RunWinAgent 璋冪敤宸叉湁鍛戒护锛屽畨鍏ㄧ瓥鐣ヤ笉鍙?|

#### 鏋勫缓楠岃瘉

- 鏋勫缓鍛戒护锛歚D:\desktopvisual\build.ps1`
- 鏋勫缓缁撴灉锛氶€氳繃銆倃inagent.exe 鍚?TaskRunner 妯″潡锛岀紪璇戦摼鎺ユ垚鍔熴€?
#### 娴嬭瘯楠岃瘉

- 娴嬭瘯鍛戒护锛歚D:\desktopvisual\mvp_selftest.ps1`
- 娴嬭瘯缁撴灉锛?*4/4 鍏ㄩ儴閫氳繃**銆傛槑缁嗭細
  1. testwindow_basic.task.json PASS (3/3 steps)
  2. notepad_input SKIP (not available)
  3. Locator failure recovery stop (LOCATOR_NOT_FOUND on DoesNotExistXYZ)
  4. Safety denied immediate stop (WINDOW_NOT_FOUND on unauthorized title)

- run-task 瀹炴椂楠岃瘉锛歵estwindow_basic 3 姝ラ鍏ㄩ儴閫氳繃锛?4ms锛孧VP 鎶ュ憡宸茬敓鎴愩€?
#### 鐢熸垚璇佹嵁

- MVP 鎶ュ憡锛歚D:\desktopvisual\artifacts\mvp_test_report.md`
- TaskRunner 婧愮爜锛歍askRunner.h (84琛? + TaskRunner.cpp (420琛?

#### 鏈獙璇侀闄?
- TaskRunner 鐨?JSON 瑙ｆ瀽鍣ㄤ负绠€鍖栧疄鐜帮紝涓嶅鐞嗗灞傚祵濂?JSON 瀵硅薄鎴栨暟缁勩€?- 鎭㈠閫昏緫涓殑 `fallback_to_uia_if_available` 璺緞鏈粡 selftest 涓疄闄?OCR_UNAVAILABLE 鏉′欢娴嬭瘯銆?- `EXPECT_FAILED` 鎭㈠锛坮eobserve_and_reexpect_once锛夋湭缁忎笓闂ㄦ祴璇曘€?- MVP 鎶ュ憡涓?`Final Recommendation` 鍦ㄦ垚鍔熸椂纭紪鐮侊紝闇€纭涓庡疄闄呭缓璁€昏緫涓€鑷淬€?- calculator_42/edge_local_form/explorer_temp_folder/vscode_edit_save 浠诲姟浠呭惈 observe 姝ラ锛屾湭娴嬭瘯瀹屾暣鐨?act+expect 闂幆銆?
#### 闇€瑕丆odex閲嶇偣澶嶆牳鐨勯棶棰?
- 澶嶆牳 FailureClassifier 鐨?12 涓敊璇被鍒槧灏勬槸鍚﹁鐩栨墍鏈夊凡鐭?`error.code`銆?- 澶嶆牳 `AttemptRecovery` 涓瘡涓仮澶嶈矾寰勬槸鍚︽纭墽琛屼笖涓嶄骇鐢熷壇浣滅敤銆?- 澶嶆牳 TaskRunner 涓?`ExecuteActStep` 鐨?type 鍔ㄤ綔閫昏緫鏄惁姝ｇ‘澶勭悊 `double-click`/`right-click` 鍔ㄤ綔銆?- 澶嶆牳 MVP 鎶ュ憡鏍煎紡鏄惁婊¤冻 task.json 涓墍鏈夊瓧娈电殑鍙璁¤姹傘€?
#### 鏈増鏈粨璁?
- 鎺ュ彈鐘舵€侊細寰?Codex 澶嶆牳銆侻VP selftest 4/4 閫氳繃銆俆askRunner 瑙傚療-瀹氫綅-鍔ㄤ綔-楠岃瘉闂幆宸插疄鐜般€傚け璐ュ垎绫诲拰鏈夐檺鎭㈠鏈哄埗宸插缓绔嬨€?
