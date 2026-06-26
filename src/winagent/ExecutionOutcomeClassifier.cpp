#include "ExecutionOutcomeClassifier.h"

#include "Trace.h"

#include <algorithm>
#include <cwctype>
#include <regex>
#include <sstream>

namespace {

std::wstring Trim(std::wstring value) {
    auto first = std::find_if_not(value.begin(), value.end(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](wchar_t ch) {
        return std::iswspace(ch) != 0;
    }).base();
    if (first >= last) return L"";
    return std::wstring(first, last);
}

std::wstring ToLowerInvariant(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return false;
    return ToLowerInvariant(haystack).find(ToLowerInvariant(needle)) != std::wstring::npos;
}

bool ContainsAnyInsensitive(const std::wstring& haystack, const std::vector<std::wstring>& needles) {
    for (const auto& needle : needles) {
        if (ContainsInsensitive(haystack, needle)) return true;
    }
    return false;
}

bool RegexSearch(const std::wstring& text, const std::wstring& pattern, std::wsmatch* match = nullptr) {
    try {
        std::wregex regex(pattern, std::regex_constants::icase);
        if (match) return std::regex_search(text, *match, regex);
        return std::regex_search(text, regex);
    } catch (...) {
        return false;
    }
}

std::vector<std::wstring> SplitLines(const std::wstring& value) {
    std::vector<std::wstring> lines;
    std::wstringstream stream(value);
    std::wstring line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == L'\r') line.pop_back();
        lines.push_back(line);
    }
    if (lines.empty() && !value.empty()) lines.push_back(value);
    return lines;
}

bool LooksLikePathToSource(const std::wstring& value) {
    return ContainsInsensitive(value, L".py") &&
           (value.find(L":\\") != std::wstring::npos || value.find(L"/") != std::wstring::npos);
}

bool LooksLikeRuntimeCommandLine(const std::wstring& line) {
    return ContainsInsensitive(line, L"python.exe") ||
           RegexSearch(line, L"(^|\\s)python(\\s|$)") ||
           (LooksLikePathToSource(line) && (ContainsInsensitive(line, L"python") || ContainsInsensitive(line, L"main.py")));
}

std::wstring FirstMatchingLine(const std::vector<std::wstring>& lines) {
    for (const auto& line : lines) {
        if (LooksLikeRuntimeCommandLine(line) ||
            ContainsInsensitive(line, L"Running") ||
            ContainsInsensitive(line, L"Process started") ||
            ContainsInsensitive(line, L"运行") ||
            ContainsInsensitive(line, L"正在运行")) {
            return Trim(line);
        }
    }
    return L"";
}

std::wstring TailExcerpt(const std::wstring& value, size_t maxChars) {
    if (value.size() <= maxChars) return value;
    return value.substr(value.size() - maxChars);
}

std::wstring StringArrayJson(const std::vector<std::wstring>& values) {
    std::wstringstream json;
    json << L"[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) json << L",";
        json << JsonString(values[i]);
    }
    json << L"]";
    return json.str();
}

bool ParseExitCode(const std::wstring& text, int& exitCode) {
    std::wsmatch match;
    if (RegexSearch(text, L"(?:exit code|退出代码(?:为)?)\\s*[:=]?\\s*(-?\\d+)", &match) && match.size() > 1) {
        try {
            exitCode = std::stoi(match[1].str());
            return true;
        } catch (...) {
            return false;
        }
    }
    return false;
}

#if 0
std::vector<std::wstring> ExtractOutputLines(const std::wstring& text) {
    std::vector<std::wstring> values;
    try {
        std::wregex regex(L"这是第\\s*([0-9]+)\\s*个输出");
        auto begin = std::wsregex_iterator(text.begin(), text.end(), regex);
        auto end = std::wsregex_iterator();
        for (auto it = begin; it != end; ++it) {
            values.push_back(it->str());
        }
    } catch (...) {
    }
    return values;
}

bool OutputSequenceIsValid(const std::vector<std::wstring>& lines) {
    if (lines.size() < 2 || lines.size() > 10) return false;
    for (size_t i = 0; i < lines.size(); ++i) {
        std::wstring expected = L"这是第" + std::to_wstring(static_cast<int>(i + 1)) + L"个输出";
        if (Trim(lines[i]) != expected) return false;
    }
    return true;
}

#endif

std::wstring LegacyChineseOutputLine(int index) {
    const wchar_t prefix[] = { static_cast<wchar_t>(36825), static_cast<wchar_t>(26159), static_cast<wchar_t>(31532), L'\0' };
    const wchar_t suffix[] = { static_cast<wchar_t>(20010), static_cast<wchar_t>(36755), static_cast<wchar_t>(20986), L'\0' };
    return std::wstring(prefix) + std::to_wstring(index) + std::wstring(suffix);
}

std::vector<std::wstring> ExtractOutputLines(const std::wstring& text) {
    std::vector<std::wstring> values;
    try {
        std::wregex regex(L"DV616_SEQ\\s+([0-9]+)\\b[^\\r\\n]*", std::regex_constants::icase);
        auto begin = std::wsregex_iterator(text.begin(), text.end(), regex);
        auto end = std::wsregex_iterator();
        for (auto it = begin; it != end; ++it) {
            values.push_back(it->str());
        }
    } catch (...) {
    }
    try {
        std::wstring legacyPattern = LegacyChineseOutputLine(0);
        legacyPattern.replace(3, 1, L"\\s*([0-9]+)\\s*");
        std::wregex regex(legacyPattern);
        auto begin = std::wsregex_iterator(text.begin(), text.end(), regex);
        auto end = std::wsregex_iterator();
        for (auto it = begin; it != end; ++it) {
            values.push_back(it->str());
        }
    } catch (...) {
    }
    return values;
}

bool OutputSequenceIsValid(const std::vector<std::wstring>& lines) {
    if (lines.size() < 2 || lines.size() > 10) return false;
    for (size_t i = 0; i < lines.size(); ++i) {
        const std::wstring line = Trim(lines[i]);
        std::wsmatch seqMatch;
        if (RegexSearch(line, L"^DV616_SEQ\\s+([0-9]+)\\b", &seqMatch) && seqMatch.size() > 1) {
            try {
                if (std::stoi(seqMatch[1].str()) != static_cast<int>(i + 1)) return false;
                continue;
            } catch (...) {
                return false;
            }
        }
        if (line != LegacyChineseOutputLine(static_cast<int>(i + 1))) return false;
    }
    return true;
}

std::wstring SummarizeError(const std::wstring& text) {
    const std::vector<std::wstring> lines = SplitLines(text);
    for (const auto& line : lines) {
        if (ContainsInsensitive(line, L"IndentationError") ||
            ContainsInsensitive(line, L"SyntaxError") ||
            ContainsInsensitive(line, L"Traceback") ||
            ContainsInsensitive(line, L"RuntimeError") ||
            ContainsInsensitive(line, L"Exception") ||
            ContainsInsensitive(line, L"error:") ||
            ContainsInsensitive(line, L"fatal error") ||
            ContainsInsensitive(line, L"BUILD FAILED") ||
            ContainsInsensitive(line, L"Build failed")) {
            return Trim(line);
        }
    }
    return L"";
}

std::wstring ErrorCategoryForText(const std::wstring& text, bool exitCodePresent, int exitCode) {
    if (ContainsInsensitive(text, L"IndentationError")) return L"SYNTAX_OR_INDENTATION_ERROR";
    if (ContainsInsensitive(text, L"SyntaxError")) return L"SYNTAX_ERROR";
    if (ContainsInsensitive(text, L"Traceback") ||
        ContainsInsensitive(text, L"RuntimeError") ||
        ContainsInsensitive(text, L"Exception")) {
        return L"RUNTIME_ERROR";
    }
    if (ContainsInsensitive(text, L"Compilation failed") ||
        ContainsInsensitive(text, L"BUILD FAILED") ||
        ContainsInsensitive(text, L"Build failed") ||
        ContainsInsensitive(text, L"fatal error") ||
        ContainsInsensitive(text, L"undefined reference") ||
        ContainsInsensitive(text, L"error:")) {
        return L"BUILD_OR_COMPILE_ERROR";
    }
    if (exitCodePresent && exitCode != 0) return L"NONZERO_EXIT_CODE";
    return L"";
}

}  // namespace

ExecutionOutcome ClassifyExecutionOutcome(const ExecutionOutcomeInput& input) {
    ExecutionOutcome outcome;
    outcome.classifierProfile = input.profile.empty() ? L"python" : input.profile;
    outcome.rawOutputExcerpt = TailExcerpt(input.afterText, 2000);
    outcome.outputLinesObserved = ExtractOutputLines(input.afterText);

    const std::vector<std::wstring> afterLines = SplitLines(input.afterText);
    outcome.runtimeCommandText = FirstMatchingLine(afterLines);
    outcome.runtimeCommandObserved = !outcome.runtimeCommandText.empty();
    outcome.compilerOrInterpreterObserved =
        ContainsInsensitive(input.afterText, L"python.exe") ||
        RegexSearch(input.afterText, L"(^|\\s)python(\\s|$)") ||
        ContainsInsensitive(input.afterText, L"javac") ||
        ContainsInsensitive(input.afterText, L"java.exe") ||
        ContainsInsensitive(input.afterText, L"g++") ||
        ContainsInsensitive(input.afterText, L"gcc") ||
        ContainsInsensitive(input.afterText, L"cl.exe") ||
        ContainsInsensitive(input.afterText, L"dotnet") ||
        ContainsInsensitive(input.afterText, L"node.exe");

    outcome.exitCodePresent = ParseExitCode(input.afterText, outcome.exitCode);
    outcome.executionCompleted =
        outcome.exitCodePresent ||
        ContainsAnyInsensitive(input.afterText, {
            L"Process finished with exit code",
            L"进程已结束",
            L"退出代码",
            L"程序已退出",
            L"Build finished",
            L"Build completed"
        });

    outcome.errorCategory = ErrorCategoryForText(input.afterText, outcome.exitCodePresent, outcome.exitCode);
    outcome.errorDetected = !outcome.errorCategory.empty();
    outcome.errorLanguageHint = (ContainsInsensitive(input.afterText, L"python") ||
                                 ContainsInsensitive(input.afterText, L".py") ||
                                 ContainsInsensitive(input.afterText, L"IndentationError") ||
                                 ContainsInsensitive(input.afterText, L"SyntaxError"))
        ? L"python"
        : L"";
    outcome.errorSummary = SummarizeError(input.afterText);
    if (outcome.errorSummary.empty() && outcome.errorDetected) {
        outcome.errorSummary = outcome.errorCategory;
    }

    const bool hasStartMarker = !input.expectedStartMarker.empty() && ContainsInsensitive(input.afterText, input.expectedStartMarker);
    const bool hasEndMarker = !input.expectedEndMarker.empty() && ContainsInsensitive(input.afterText, input.expectedEndMarker);
    const bool hasOutputLines = !outcome.outputLinesObserved.empty();
    const bool hasRuntimeSignal = outcome.runtimeCommandObserved || outcome.compilerOrInterpreterObserved;
    const bool hasStartSignal = hasRuntimeSignal || hasStartMarker || ContainsAnyInsensitive(input.afterText, {
        L"Running",
        L"Process started",
        L"运行",
        L"正在运行"
    });

    outcome.runTriggered =
        hasStartSignal ||
        outcome.executionCompleted ||
        outcome.errorDetected ||
        hasOutputLines ||
        hasEndMarker;
    outcome.executionStarted =
        outcome.runTriggered &&
        (hasStartSignal || outcome.errorDetected || hasOutputLines || LooksLikePathToSource(input.afterText));

    outcome.oldOutputReuseDetected = !Trim(input.afterText).empty() && Trim(input.beforeText) == Trim(input.afterText);
    outcome.expectedOutputVerified = hasStartMarker && hasEndMarker && OutputSequenceIsValid(outcome.outputLinesObserved);
    outcome.executionSuccess =
        outcome.executionCompleted &&
        outcome.exitCodePresent &&
        outcome.exitCode == 0 &&
        !outcome.errorDetected;
    outcome.currentRunVerified =
        !outcome.oldOutputReuseDetected &&
        outcome.runTriggered &&
        (
            (hasStartMarker && hasEndMarker) ||
            (Trim(input.beforeText) != Trim(input.afterText) &&
                (outcome.executionCompleted || outcome.errorDetected || hasRuntimeSignal))
        );

    if (!outcome.runTriggered) {
        outcome.classifierConfidence = 0.25;
    } else if (outcome.executionSuccess && outcome.expectedOutputVerified && outcome.currentRunVerified) {
        outcome.classifierConfidence = 0.95;
    } else if (outcome.errorDetected && outcome.executionCompleted) {
        outcome.classifierConfidence = 0.92;
    } else if (outcome.executionCompleted || hasRuntimeSignal) {
        outcome.classifierConfidence = 0.80;
    } else {
        outcome.classifierConfidence = 0.55;
    }
    return outcome;
}

std::wstring ExecutionOutcomeJson(const ExecutionOutcome& outcome) {
    std::wstringstream json;
    json << L"{\"run_triggered\":" << (outcome.runTriggered ? L"true" : L"false")
         << L",\"execution_started\":" << (outcome.executionStarted ? L"true" : L"false")
         << L",\"execution_completed\":" << (outcome.executionCompleted ? L"true" : L"false")
         << L",\"execution_success\":" << (outcome.executionSuccess ? L"true" : L"false")
         << L",\"exit_code_present\":" << (outcome.exitCodePresent ? L"true" : L"false")
         << L",\"exit_code\":";
    if (outcome.exitCodePresent) {
        json << outcome.exitCode;
    } else {
        json << L"null";
    }
    json << L",\"runtime_command_observed\":" << (outcome.runtimeCommandObserved ? L"true" : L"false")
         << L",\"runtime_command_text\":" << JsonString(outcome.runtimeCommandText)
         << L",\"compiler_or_interpreter_observed\":" << (outcome.compilerOrInterpreterObserved ? L"true" : L"false")
         << L",\"error_detected\":" << (outcome.errorDetected ? L"true" : L"false")
         << L",\"error_category\":" << JsonString(outcome.errorCategory)
         << L",\"error_language_hint\":" << JsonString(outcome.errorLanguageHint)
         << L",\"error_summary\":" << JsonString(outcome.errorSummary)
         << L",\"output_lines_observed\":" << StringArrayJson(outcome.outputLinesObserved)
         << L",\"output_count\":" << outcome.outputLinesObserved.size()
         << L",\"expected_output_verified\":" << (outcome.expectedOutputVerified ? L"true" : L"false")
         << L",\"current_run_verified\":" << (outcome.currentRunVerified ? L"true" : L"false")
         << L",\"old_output_reuse_detected\":" << (outcome.oldOutputReuseDetected ? L"true" : L"false")
         << L",\"raw_output_excerpt\":" << JsonString(outcome.rawOutputExcerpt)
         << L",\"classifier_profile\":" << JsonString(outcome.classifierProfile)
         << L",\"classifier_confidence\":" << outcome.classifierConfidence
         << L"}";
    return json.str();
}
