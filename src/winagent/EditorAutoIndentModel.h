#pragma once

#include "IndentationController.h"
#include "LanguageScopeModel.h"

#include <string>
#include <vector>

struct EditorAutoIndentModelResult {
    bool ok = true;
    bool editorAutoIndentModel = true;
    bool naturalAutoIndentFollowed = false;
    bool minimalIndentCorrection = true;
    int explicitCorrectionLineCount = 0;
    int actualIndentCorrectionKeys = 0;
    std::vector<IndentationLinePlan> linePlans;
};

EditorAutoIndentModelResult BuildEditorAutoIndentPlan(
    const std::vector<StructuredCodeLine>& lines,
    const LanguageScopeModelResult& scopeModel,
    const IndentationOptions& options);
std::wstring EditorAutoIndentModelResultJson(const EditorAutoIndentModelResult& result);
