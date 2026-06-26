#pragma once

#include <string>
#include <vector>

struct RecoveryStrategy {
    std::wstring errorCode;
    std::wstring strategyName;
    std::vector<std::wstring> steps;
    bool canAttempt = false;
    std::wstring stopReason;
};

struct RecoveryAttemptRecord {
    int stepIndex = -1;
    std::wstring stepName;
    std::wstring errorCode;
    std::wstring strategyName;
    int attempt = 0;
    std::wstring result;
    std::wstring details;
    std::vector<std::wstring> strategySteps;
};

RecoveryStrategy StrategyForError(const std::wstring& errorCode);

