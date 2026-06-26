#pragma once

#include <string>

bool IsRuntimeSessionCommand(const std::wstring& command);
bool IsRuntimeSessionCompatibleLegacyCommand(const std::wstring& command);
bool RuntimeSessionArgPresent(int argc, wchar_t** argv);
int DispatchRuntimeSessionCommandLine(int argc, wchar_t** argv);
