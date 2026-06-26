#pragma once

#include "WindowFinder.h"

#include <string>

struct ExplorerContextMenuResult {
    bool ok = false;
    std::wstring errorCode;
    std::wstring errorMessage;
    bool rightClickSent = false;
    bool contextMenuVisible = false;
    bool menuItemLocated = false;
    bool menuItemClicked = false;
    std::wstring action;
    std::wstring evidenceJson;
};

ExplorerContextMenuResult ExecuteExplorerContextMenuAction(
    const WindowInfo& explorerWindow,
    int clientX,
    int clientY,
    const std::wstring& action,
    const std::wstring& inputText);

