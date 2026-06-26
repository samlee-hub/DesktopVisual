#pragma once

#include <string>
#include <vector>

struct ProfileLocator {
    std::wstring name;
    std::wstring selector;
    std::wstring semanticStatus;
    std::wstring riskStatus;
};

struct AppProfile {
    std::wstring path;
    std::wstring profileName;
    std::wstring appKind;
    std::wstring processMatch;
    std::wstring titleMatch;
    std::wstring windowClassMatch;
    std::wstring allowedWindowScope;
    std::wstring version;
    std::wstring notes;
    std::vector<ProfileLocator> commonLocators;
    bool hasRoiDefinitions = false;
    bool hasVisualStrategy = false;
    bool hasOcrStrategy = false;
    bool hasRecoveryStrategy = false;
    bool hasSafetyOverrides = false;
    bool hasTaskTemplates = false;
    bool hasConfirmationNodes = false;
    bool valid = false;
    std::vector<std::wstring> errors;
    std::vector<std::wstring> warnings;
};

struct ProfileLoadReport {
    std::vector<AppProfile> profiles;
    int loadedCount = 0;
    int invalidCount = 0;
};

std::wstring ProfilesRootPath();
AppProfile LoadAppProfileFile(const std::wstring& path);
ProfileLoadReport LoadAppProfiles(const std::wstring& path);
bool ResolveProfileLocator(
    const std::wstring& profileName,
    const std::wstring& locatorName,
    AppProfile& profile,
    ProfileLocator& locator,
    std::wstring& error);
std::wstring ProfileLoadReportJson(const ProfileLoadReport& report);
std::wstring ProfileLocatorCandidateJson(const AppProfile& profile, const ProfileLocator& locator);
