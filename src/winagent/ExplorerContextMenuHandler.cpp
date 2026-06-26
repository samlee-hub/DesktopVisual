#include "ExplorerContextMenuHandler.h"

#include "InputController.h"
#include "SafetyPolicy.h"
#include "Trace.h"
#include "UiaController.h"

#include <windows.h>

#include <algorithm>
#include <cwctype>

namespace {

std::wstring Lower(std::wstring value) {
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
        return static_cast<wchar_t>(std::towlower(ch));
    });
    return value;
}

bool MenuActionMatches(const std::wstring& name, const std::wstring& action) {
    std::wstring n = Lower(name);
    std::wstring a = Lower(action);
    if (a.empty() || a == L"rename") {
        return n.find(L"rename") != std::wstring::npos || n.find(L"\u91cd\u547d\u540d") != std::wstring::npos;
    }
    if (a == L"delete") {
        return n.find(L"delete") != std::wstring::npos || n.find(L"\u5220\u9664") != std::wstring::npos;
    }
    if (a == L"cut") {
        return n.find(L"cut") != std::wstring::npos || n.find(L"\u526a\u5207") != std::wstring::npos;
    }
    if (a == L"paste") {
        return n.find(L"paste") != std::wstring::npos || n.find(L"\u7c98\u8d34") != std::wstring::npos;
    }
    return n.find(a) != std::wstring::npos;
}

}  // namespace

ExplorerContextMenuResult ExecuteExplorerContextMenuAction(
    const WindowInfo& explorerWindow,
    int clientX,
    int clientY,
    const std::wstring& action,
    const std::wstring& inputText) {
    ExplorerContextMenuResult result;
    result.action = action;
    if (!explorerWindow.hwnd || !IsWindow(explorerWindow.hwnd)) {
        result.errorCode = L"STOP_CONTEXT_MENU_NOT_FOUND";
        result.errorMessage = L"Explorer window is not available.";
        return result;
    }

    ClickResult right = RightClickClientPoint(explorerWindow.hwnd, clientX, clientY, L"human", 0);
    result.rightClickSent = right.ok;
    if (!right.ok) {
        result.errorCode = right.errorCode.empty() ? L"SEND_INPUT_FAILED" : right.errorCode;
        result.errorMessage = right.error;
        return result;
    }
    Sleep(350);

    HWND foreground = GetForegroundWindow();
    result.contextMenuVisible = foreground != nullptr;
    WindowInfo menuWindow = explorerWindow;
    if (foreground && foreground != explorerWindow.hwnd) {
        menuWindow.hwnd = foreground;
        GetWindowThreadProcessId(foreground, &menuWindow.pid);
        GetWindowRect(foreground, &menuWindow.rect);
        menuWindow.title = L"context menu";
    }

    UiaQueryResult tree = ReadUiaTree(menuWindow.hwnd);
    UiaElementInfo menuItem;
    std::vector<UiaElementInfo> menuItemMatches;
    std::vector<UiaElementInfo> buttonMatches;
    std::vector<UiaElementInfo> otherMatches;
    if (tree.ok) {
        for (const auto& element : tree.elements) {
            if (!element.enabled || element.offscreen) continue;
            if (element.rect.right <= element.rect.left || element.rect.bottom <= element.rect.top) continue;
            if (MenuActionMatches(element.name, action)) {
                if (element.controlType == L"MenuItem") {
                    menuItemMatches.push_back(element);
                } else if (element.controlType == L"Button") {
                    buttonMatches.push_back(element);
                } else {
                    otherMatches.push_back(element);
                }
            }
        }
    }
    const std::vector<UiaElementInfo>& matches =
        !menuItemMatches.empty() ? menuItemMatches : (!buttonMatches.empty() ? buttonMatches : otherMatches);
    if (matches.size() > 1) {
        result.errorCode = L"STOP_TARGET_NOT_UNIQUE";
        result.errorMessage = L"Context menu item matched multiple elements.";
        result.contextMenuVisible = true;
        return result;
    }
    if (matches.empty()) {
        result.errorCode = L"STOP_CONTEXT_MENU_NOT_FOUND";
        result.errorMessage = L"Context menu item was not found.";
        return result;
    }

    menuItem = matches.front();
    result.menuItemLocated = true;
    POINT pt{(menuItem.rect.left + menuItem.rect.right) / 2, (menuItem.rect.top + menuItem.rect.bottom) / 2};
    ScreenToClient(menuWindow.hwnd, &pt);
    ClickResult clicked = ClickClientPoint(menuWindow.hwnd, pt.x, pt.y, L"human", 0);
    result.menuItemClicked = clicked.ok;
    if (!clicked.ok) {
        result.errorCode = clicked.errorCode.empty() ? L"SEND_INPUT_FAILED" : clicked.errorCode;
        result.errorMessage = clicked.error;
        return result;
    }

    if (!inputText.empty()) {
        Sleep(200);
        TypeResult typed = TypeText(explorerWindow.hwnd, inputText, L"human", -1);
        if (!typed.ok) {
            result.errorCode = typed.errorCode.empty() ? L"SEND_INPUT_FAILED" : typed.errorCode;
            result.errorMessage = typed.error;
            return result;
        }
        ActionResult enter = PressKey(explorerWindow.hwnd, L"ENTER");
        if (!enter.ok) {
            result.errorCode = enter.errorCode.empty() ? L"SEND_INPUT_FAILED" : enter.errorCode;
            result.errorMessage = enter.error;
            return result;
        }
    }

    result.ok = true;
    result.evidenceJson = L"{\"right_click_sent\":" + std::wstring(result.rightClickSent ? L"true" : L"false")
        + L",\"context_menu_visible\":" + std::wstring(result.contextMenuVisible ? L"true" : L"false")
        + L",\"menu_item_located\":" + std::wstring(result.menuItemLocated ? L"true" : L"false")
        + L",\"menu_item_clicked\":" + std::wstring(result.menuItemClicked ? L"true" : L"false")
        + L",\"action\":" + JsonString(action) + L"}";
    return result;
}
