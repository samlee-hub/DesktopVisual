#pragma once

#include "InputController.h"

#include <windows.h>

#include <string>
#include <vector>

struct CursorAndBufferStateGuardResult {
    bool ok = true;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool cursorAndBufferStateGuard = true;
    bool targetEditorFocused = false;
    bool cursorBufferStateVerified = false;
    bool oldBufferClearedOrSafeReplaceVerified = false;
    bool noRetryContamination = false;
    bool visibleBufferClearVerified = false;
    bool clearContaminationDetected = false;
    bool clearFirst = true;
    bool visibleVerificationRequired = true;
    std::wstring clearStrategy = L"reverse_full_buffer_selection_delete";
    std::vector<std::wstring> keySequence;
    int keyboardSendBatchCount = 0;
};

CursorAndBufferStateGuardResult PlanCursorAndBufferStateGuard(bool clearFirst);
CursorAndBufferStateGuardResult ClearCodeEditorBufferForRewrite(HWND hwnd, bool dryRun, bool clearFirst);
std::wstring CursorAndBufferStateGuardResultJson(const CursorAndBufferStateGuardResult& result);
