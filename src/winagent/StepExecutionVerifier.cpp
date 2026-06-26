#include "StepExecutionVerifier.h"

#include "CaseRunner.h"
#include "ProjectRoot.h"
#include "Trace.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>
#include <iostream>
#include <sstream>

namespace {

bool ArgValue(int argc, wchar_t** argv, const std::wstring& name, std::wstring& value) {
    for (int i = 2; i + 1 < argc; ++i) {
        if (argv[i] == name) {
            value = argv[i + 1];
            return true;
        }
    }
    return false;
}

bool WriteTextFileUtf8(const std::wstring& path, const std::wstring& text, std::wstring& error) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) EnsureDirectoryPath(path.substr(0, slash));
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"w, ccs=UTF-8") != 0 || !file) {
        error = L"Could not write file.";
        return false;
    }
    fwprintf(file, L"%ls", text.c_str());
    fclose(file);
    return true;
}

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool ContainsInsensitive(const std::wstring& haystack, const std::wstring& needle) {
    if (needle.empty()) return true;
    return Lower(haystack).find(Lower(needle)) != std::wstring::npos;
}

bool FileExists(const std::wstring& path) {
    if (path.empty()) return false;
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring VerificationJson(
    bool ok,
    const std::wstring& stepId,
    int stepIndex,
    const std::wstring& type,
    const std::wstring& evidence,
    const std::wstring& stopCode,
    const std::wstring& attribution) {
    std::wstringstream json;
    json << L"{\"schema_version\":\"6.4.0.step_execution_verification\""
         << L",\"step_id\":" << JsonString(stepId)
         << L",\"step_index\":" << stepIndex
         << L",\"verification_ok\":" << (ok ? L"true" : L"false")
         << L",\"verification_type\":" << JsonString(type)
         << L",\"verification_evidence\":" << JsonString(evidence)
         << L",\"stop_code\":" << JsonString(stopCode)
         << L",\"failure_attribution\":" << JsonString(attribution)
         << L"}";
    return json.str();
}

StepExecutionVerificationResult BuildResult(
    bool ok,
    const StepExecutionVerificationInput& input,
    const std::wstring& type,
    const std::wstring& evidence,
    const std::wstring& stopCode,
    const std::wstring& attribution) {
    StepExecutionVerificationResult result;
    result.verificationOk = ok;
    result.verificationType = type;
    result.evidence = evidence;
    result.stopCode = stopCode;
    result.failureAttribution = attribution;
    result.resultJson = VerificationJson(ok, input.stepId, input.stepIndex, type, evidence, stopCode, attribution);
    return result;
}

}  // namespace

StepExecutionVerificationResult VerifyStepExecution(const StepExecutionVerificationInput& input) {
    if (!input.verificationHint || !input.verificationHint->IsObject()) {
        return BuildResult(false, input, L"", L"missing verification_hint", L"STOP_MISSING_VERIFICATION_HINT", L"verification_hint_missing");
    }

    std::wstring type = simplejson::GetString(*input.verificationHint, L"verify_type");
    if (type.empty()) {
        return BuildResult(false, input, type, L"verification_hint.verify_type missing", L"STOP_MISSING_VERIFICATION_HINT", L"verification_hint_missing");
    }

    if (input.wrongContextDetected) {
        return BuildResult(false, input, type, L"wrong context detected", L"STOP_WRONG_CONTEXT", L"runtime_context_guard");
    }
    if (input.wrongFieldDetected) {
        return BuildResult(false, input, type, L"wrong field detected", L"STOP_WRONG_FIELD", L"field_guard");
    }

    std::wstring expectedMarker = simplejson::GetString(*input.verificationHint, L"expected_marker");
    std::wstring expectedText = simplejson::GetString(*input.verificationHint, L"expected_text");
    std::wstring expectedWindowTitle = simplejson::GetString(*input.verificationHint, L"expected_window_title");
    std::wstring expectedUrl = simplejson::GetString(*input.verificationHint, L"expected_url_pattern");
    std::wstring expectedOutput = simplejson::GetString(*input.verificationHint, L"expected_output_pattern");
    std::wstring expectedField = simplejson::GetString(*input.verificationHint, L"expected_field_value");

    bool ok = false;
    std::wstring evidence;
    if (type == L"verify_marker" || type == L"verify_required_marker") {
        ok = ContainsInsensitive(input.contextText + L" " + input.target + L" " + input.windowTitle, expectedMarker);
        evidence = L"marker=" + expectedMarker;
    } else if (type == L"verify_page_loaded") {
        ok = ContainsInsensitive(input.contextText + L" " + input.windowTitle, expectedMarker) ||
             ContainsInsensitive(input.windowTitle, expectedWindowTitle) ||
             ContainsInsensitive(input.url + L" " + input.target, expectedUrl);
        evidence = L"page_loaded marker=" + expectedMarker + L";title=" + input.windowTitle + L";url=" + input.url;
    } else if (type == L"verify_title") {
        ok = ContainsInsensitive(input.windowTitle, expectedWindowTitle.empty() ? input.target : expectedWindowTitle);
        evidence = L"title=" + input.windowTitle;
    } else if (type == L"verify_url_pattern") {
        ok = ContainsInsensitive(input.url + L" " + input.target, expectedUrl);
        evidence = L"url=" + input.url;
    } else if (type == L"verify_text_present") {
        ok = ContainsInsensitive(input.contextText + L" " + input.outputText + L" " + input.inputText, expectedText);
        evidence = L"text=" + expectedText;
    } else if (type == L"verify_field_focused") {
        ok = !input.wrongFieldDetected;
        evidence = L"field_focus_guard=true";
    } else if (type == L"verify_field_value") {
        std::wstring expected = expectedField.empty() ? input.inputText : expectedField;
        ok = !expected.empty() && (input.fieldValue == expected || input.inputText == expected || ContainsInsensitive(input.contextText, expected));
        evidence = L"field_value=" + expected;
    } else if (type == L"verify_submit_result") {
        std::wstring expected = expectedOutput.empty() ? expectedMarker : expectedOutput;
        ok = !expected.empty() && ContainsInsensitive(input.contextText + L" " + input.outputText + L" " + input.windowTitle, expected);
        evidence = L"submit_result=" + expected;
    } else if (type == L"verify_scroll_progress") {
        ok = ContainsInsensitive(input.contextText + L" " + input.outputText + L" " + input.target, expectedText.empty() ? expectedMarker : expectedText);
        evidence = L"scroll_or_locate=" + (expectedText.empty() ? expectedMarker : expectedText);
    } else if (type == L"verify_wrong_page_stop") {
        ok = input.wrongContextDetected;
        evidence = L"wrong_page_stop_expected";
    } else if (type == L"verify_active_protection_stop" || type == L"verify_credential_required_stop") {
        ok = true;
        evidence = L"blocked stop verification type accepted for non-executable workflow";
    } else if (type == L"verify_window_title") {
        ok = ContainsInsensitive(input.windowTitle, expectedWindowTitle.empty() ? input.target : expectedWindowTitle);
        evidence = L"window_title=" + input.windowTitle;
    } else if (type == L"verify_file_exists") {
        std::wstring path = expectedText.empty() ? input.target : expectedText;
        ok = FileExists(path);
        evidence = L"file_exists=" + path;
    } else if (type == L"verify_file_deleted") {
        std::wstring path = expectedText.empty() ? input.target : expectedText;
        ok = !FileExists(path);
        evidence = L"file_deleted=" + path;
    } else if (type == L"verify_url_or_page_marker") {
        ok = ContainsInsensitive(input.url, expectedUrl) || ContainsInsensitive(input.contextText, expectedMarker);
        evidence = L"url=" + input.url + L";marker=" + expectedMarker;
    } else if (type == L"verify_output_pattern") {
        ok = ContainsInsensitive(input.outputText, expectedOutput.empty() ? expectedText : expectedOutput);
        evidence = L"output=" + input.outputText;
    } else if (type == L"verify_communication_created") {
        std::wstring expected = expectedOutput.empty() ? expectedText : expectedOutput;
        std::wstring haystack = input.contextText + L" " + input.outputText + L" " + input.target + L" " + input.inputText;
        ok = !expected.empty() && ContainsInsensitive(haystack, expected);
        evidence = L"communication_created=" + expected;
    } else if (type == L"verify_no_wrong_context") {
        ok = !input.wrongContextDetected;
        evidence = L"wrong_context_detected=false";
    } else if (type == L"verify_no_wrong_field") {
        ok = !input.wrongFieldDetected;
        evidence = L"wrong_field_detected=false";
    } else {
        ok = false;
        evidence = L"unsupported verification type";
    }

    return BuildResult(
        ok,
        input,
        type,
        evidence,
        ok ? L"" : L"STOP_UNVERIFIED_RESULT",
        ok ? L"" : L"step_execution_verifier");
}

int CommandStepExecutionVerify(int argc, wchar_t** argv) {
    const std::wstring command = L"step-execution-verify";
    ULONGLONG startTick = GetTickCount64();
    std::wstring inputPath;
    std::wstring outputPath;
    if (!ArgValue(argc, argv, L"--input", inputPath) || inputPath.empty()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"INVALID_ARGUMENT", L"step-execution-verify requires --input.", L"{}") << L"\n";
        return 2;
    }
    ArgValue(argc, argv, L"--output", outputPath);
    FileReadResult read = ReadTextFile(inputPath);
    if (!read.ok) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), read.errorCode.empty() ? L"FILE_READ_FAILED" : read.errorCode, read.error, L"{}") << L"\n";
        return 2;
    }
    simplejson::ParseResult parsed = simplejson::Parse(read.content);
    if (!parsed.ok || !parsed.root.IsObject()) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), L"COMPILE_SCHEMA_INVALID", L"Input JSON is malformed.", L"{}") << L"\n";
        return 2;
    }
    StepExecutionVerificationInput input;
    input.stepId = simplejson::GetString(parsed.root, L"step_id");
    input.stepIndex = simplejson::GetInt(parsed.root, L"step_index", 0);
    input.runtimeAction = simplejson::GetString(parsed.root, L"runtime_action");
    input.target = simplejson::GetString(parsed.root, L"target");
    input.inputText = simplejson::GetString(parsed.root, L"input_text");
    input.verificationHint = simplejson::Find(parsed.root, L"verification_hint");
    if (const simplejson::Value* state = simplejson::Find(parsed.root, L"execution_state"); state && state->IsObject()) {
        input.contextText = simplejson::GetString(*state, L"context_text");
        input.fieldValue = simplejson::GetString(*state, L"field_value");
        input.windowTitle = simplejson::GetString(*state, L"window_title");
        input.url = simplejson::GetString(*state, L"url");
        input.outputText = simplejson::GetString(*state, L"output_text");
        input.wrongContextDetected = simplejson::GetBool(*state, L"wrong_context_detected", false);
        input.wrongFieldDetected = simplejson::GetBool(*state, L"wrong_field_detected", false);
    }

    StepExecutionVerificationResult result = VerifyStepExecution(input);
    if (!outputPath.empty()) {
        std::wstring writeError;
        WriteTextFileUtf8(outputPath, result.resultJson, writeError);
    }
    if (!result.verificationOk) {
        std::wcout << CommandFailureJson(command, startTick, NoTraceTarget(), result.stopCode.empty() ? L"STOP_UNVERIFIED_RESULT" : result.stopCode, L"Step verification failed.", result.resultJson) << L"\n";
        return 1;
    }
    std::wcout << CommandSuccessJson(command, startTick, NoTraceTarget(), result.resultJson) << L"\n";
    return 0;
}
