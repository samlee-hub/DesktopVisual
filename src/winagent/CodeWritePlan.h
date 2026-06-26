#pragma once

#include "EditorAutoIndentModel.h"
#include "IndentationController.h"
#include "LanguageScopeModel.h"

#include <string>
#include <vector>

struct CodeMethodPlan {
    std::wstring name;
    std::wstring signature;
    std::wstring className;
    std::wstring receiverToken;
    int lineIndex = 0;
    int targetIndentSpaces = 0;
    bool constructor = false;
    bool hasReceiver = false;
    bool expectedScopeClass = true;
};

struct CodeFunctionPlan {
    std::wstring name;
    std::wstring signature;
    std::wstring receiverToken;
    int lineIndex = 0;
    int targetIndentSpaces = 0;
    bool mainFunction = false;
    bool hasReceiver = false;
};

struct CodeClassPlan {
    std::wstring name;
    int lineIndex = 0;
    int targetIndentSpaces = 0;
    std::vector<CodeMethodPlan> methods;
};

struct CodeStatementPlan {
    std::wstring text;
    std::wstring expectedScope;
    int lineIndex = 0;
    int targetIndentSpaces = 0;
};

struct CodeIncludeImportPlan {
    std::wstring text;
    int lineIndex = 0;
    int targetIndentSpaces = 0;
};

struct CodeWritePlanResult {
    bool ok = true;
    bool codeWritePlan = true;
    bool singleFilePlan = true;
    bool multiFilePlanRequired = false;
    std::wstring language = L"unknown";
    std::wstring sourceText;
    std::wstring targetFilePath;
    std::vector<StructuredCodeLine> lines;
    std::vector<CodeClassPlan> classes;
    std::vector<CodeFunctionPlan> topLevelFunctions;
    std::vector<CodeFunctionPlan> mainFunctions;
    std::vector<CodeIncludeImportPlan> importIncludeSection;
    std::vector<CodeStatementPlan> topLevelStatements;
    LanguageScopeModelResult languageScope;
    EditorAutoIndentModelResult editorAutoIndent;
    std::vector<std::wstring> findings;
};

CodeWritePlanResult BuildCodeWritePlan(const std::wstring& text, const IndentationOptions& options);
std::wstring CodeWritePlanResultJson(const CodeWritePlanResult& result);
