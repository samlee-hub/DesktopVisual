#pragma once

#include <string>

std::wstring ProjectRootPath();
std::wstring ProjectPath(const std::wstring& relativePath);
std::wstring ArtifactsPath(const std::wstring& relativePath = L"");
std::wstring ConfigPath(const std::wstring& relativePath = L"");
bool EnsureDirectoryPath(const std::wstring& path);
