#include "ProjectRoot.h"

#include <windows.h>

#include <iostream>

namespace {

std::wstring TrimTrailingSlash(std::wstring path) {
    while (path.size() > 3 && (path.back() == L'\\' || path.back() == L'/')) {
        path.pop_back();
    }
    return path;
}

std::wstring DirectoryOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return L"";
    }
    if (slash == 2 && path.size() >= 3 && path[1] == L':') {
        return path.substr(0, 3);
    }
    return path.substr(0, slash);
}

std::wstring NormalizePath(const std::wstring& path) {
    DWORD required = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (required == 0) {
        return TrimTrailingSlash(path);
    }
    std::wstring buffer(required, L'\0');
    DWORD written = GetFullPathNameW(path.c_str(), required, buffer.data(), nullptr);
    if (written == 0 || written >= required) {
        return TrimTrailingSlash(path);
    }
    buffer.resize(written);
    return TrimTrailingSlash(buffer);
}

bool HasRootMarkers(const std::wstring& path) {
    DWORD version = GetFileAttributesW((path + L"\\VERSION").c_str());
    DWORD src = GetFileAttributesW((path + L"\\src").c_str());
    return version != INVALID_FILE_ATTRIBUTES &&
           (version & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
           src != INVALID_FILE_ATTRIBUTES &&
           (src & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool HasRuntimeMarkers(const std::wstring& path) {
    DWORD version = GetFileAttributesW((path + L"\\VERSION").c_str());
    DWORD config = GetFileAttributesW((path + L"\\config").c_str());
    return version != INVALID_FILE_ATTRIBUTES &&
           (version & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
           config != INVALID_FILE_ATTRIBUTES &&
           (config & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

std::wstring FindUpward(std::wstring start, bool runtimeMarkers) {
    start = NormalizePath(start);
    while (!start.empty()) {
        if (runtimeMarkers ? HasRuntimeMarkers(start) : HasRootMarkers(start)) {
            return start;
        }
        std::wstring parent = DirectoryOf(start);
        if (parent.empty() || parent == start) {
            break;
        }
        start = parent;
    }
    return L"";
}

std::wstring ExeDirectory() {
    wchar_t modulePath[MAX_PATH] = {};
    DWORD length = GetModuleFileNameW(nullptr, modulePath, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return L"";
    }
    return DirectoryOf(modulePath);
}

std::wstring ComputeProjectRoot() {
    wchar_t envRoot[MAX_PATH] = {};
    DWORD envLen = GetEnvironmentVariableW(L"DESKTOPVISUAL_ROOT", envRoot, MAX_PATH);
    if (envLen > 0 && envLen < MAX_PATH) {
        return NormalizePath(envRoot);
    }

    std::wstring exeDir = ExeDirectory();
    if (!exeDir.empty()) {
        std::wstring fromExe = FindUpward(exeDir, false);
        if (!fromExe.empty()) {
            return fromExe;
        }
    }

    wchar_t current[MAX_PATH] = {};
    if (GetCurrentDirectoryW(MAX_PATH, current) > 0) {
        std::wstring fromCwd = FindUpward(current, true);
        if (!fromCwd.empty()) {
            return fromCwd;
        }
    }

    std::wcerr << L"WARNING: DesktopVisual root was not found from DESKTOPVISUAL_ROOT, executable path, or current directory. Falling back to D:\\desktopvisual." << std::endl;
    return L"D:\\desktopvisual";
}

std::wstring JoinPath(const std::wstring& root, const std::wstring& relativePath) {
    if (relativePath.empty()) {
        return root;
    }
    if (relativePath.size() >= 2 && relativePath[1] == L':') {
        return NormalizePath(relativePath);
    }
    if (!relativePath.empty() && (relativePath[0] == L'\\' || relativePath[0] == L'/')) {
        return NormalizePath(relativePath);
    }
    return NormalizePath(root + L"\\" + relativePath);
}

}  // namespace

std::wstring ProjectRootPath() {
    static std::wstring root = ComputeProjectRoot();
    return root;
}

std::wstring ProjectPath(const std::wstring& relativePath) {
    return JoinPath(ProjectRootPath(), relativePath);
}

std::wstring ArtifactsPath(const std::wstring& relativePath) {
    return ProjectPath(relativePath.empty() ? L"artifacts" : L"artifacts\\" + relativePath);
}

std::wstring ConfigPath(const std::wstring& relativePath) {
    return ProjectPath(relativePath.empty() ? L"config" : L"config\\" + relativePath);
}

bool EnsureDirectoryPath(const std::wstring& path) {
    if (path.empty()) {
        return false;
    }
    std::wstring normalized = NormalizePath(path);
    if (normalized.size() <= 3) {
        return true;
    }
    std::wstring parent = DirectoryOf(normalized);
    if (!parent.empty() && parent != normalized) {
        EnsureDirectoryPath(parent);
    }
    DWORD attrs = GetFileAttributesW(normalized.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES) {
        return (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
    }
    return CreateDirectoryW(normalized.c_str(), nullptr) != FALSE || GetLastError() == ERROR_ALREADY_EXISTS;
}
