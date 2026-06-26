#pragma once

#include "IndentationController.h"

#include <string>
#include <vector>

struct LanguageScopeLine {
    int lineIndex = 0;
    std::wstring contentWithoutIndent;
    int targetIndentSpaces = 0;
    int scopeDepthBefore = 0;
    int scopeDepthAfter = 0;
    bool isBlankLine = false;
    bool opensScope = false;
    bool closesScope = false;
    bool isMainFunction = false;
    bool isFunctionDeclaration = false;
    bool isClassDeclaration = false;
    bool isIncludeOrImport = false;
    bool insideMainBefore = false;
    bool invalidFunctionInsideMain = false;
    bool invalidMainInsideFunction = false;
    bool invalidIncludeOrImportInScope = false;
    bool invalidMethodOutsideClass = false;
};

struct LanguageScopeModelResult {
    bool ok = true;
    std::wstring language = L"unknown";
    bool languageScopeModel = true;
    bool functionNotNestedInMain = true;
    bool mainNotNestedInFunction = true;
    bool includeImportTopLevelVerified = true;
    bool classScopeVerified = true;
    std::vector<LanguageScopeLine> lines;
    std::vector<std::wstring> findings;
};

std::wstring DetectCodeLanguage(const std::vector<StructuredCodeLine>& lines);
LanguageScopeModelResult AnalyzeLanguageScope(const std::vector<StructuredCodeLine>& lines, const IndentationOptions& options);
std::wstring LanguageScopeLineJson(const LanguageScopeLine& line);
std::wstring LanguageScopeModelResultJson(const LanguageScopeModelResult& result);
