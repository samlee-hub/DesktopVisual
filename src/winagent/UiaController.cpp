#include "UiaController.h"

#include <UIAutomation.h>
#include <OleAuto.h>

#include <functional>
#include <sstream>
#include <vector>

namespace {

template <typename T>
void SafeRelease(T*& value) {
    if (value) {
        value->Release();
        value = nullptr;
    }
}

class ComApartment {
public:
    ComApartment() {
        hr_ = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        initialized_ = (hr_ == S_OK || hr_ == S_FALSE);
    }

    ~ComApartment() {
        if (initialized_) {
            CoUninitialize();
        }
    }

    HRESULT hr() const {
        return hr_;
    }

    bool ok() const {
        return initialized_ || hr_ == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT hr_ = E_FAIL;
    bool initialized_ = false;
};

std::wstring HResultMessage(HRESULT hr) {
    std::wstringstream stream;
    stream << L"HRESULT 0x" << std::hex << static_cast<unsigned long>(hr);
    return stream.str();
}

std::wstring BstrToString(BSTR value) {
    if (!value) {
        return L"";
    }
    std::wstring text(value, SysStringLen(value));
    SysFreeString(value);
    return text;
}

std::wstring ControlTypeName(CONTROLTYPEID controlType) {
    switch (controlType) {
        case UIA_ButtonControlTypeId: return L"Button";
        case UIA_CalendarControlTypeId: return L"Calendar";
        case UIA_CheckBoxControlTypeId: return L"CheckBox";
        case UIA_ComboBoxControlTypeId: return L"ComboBox";
        case UIA_CustomControlTypeId: return L"Custom";
        case UIA_DataGridControlTypeId: return L"DataGrid";
        case UIA_DataItemControlTypeId: return L"DataItem";
        case UIA_DocumentControlTypeId: return L"Document";
        case UIA_EditControlTypeId: return L"Edit";
        case UIA_GroupControlTypeId: return L"Group";
        case UIA_HeaderControlTypeId: return L"Header";
        case UIA_HeaderItemControlTypeId: return L"HeaderItem";
        case UIA_HyperlinkControlTypeId: return L"Hyperlink";
        case UIA_ImageControlTypeId: return L"Image";
        case UIA_ListControlTypeId: return L"List";
        case UIA_ListItemControlTypeId: return L"ListItem";
        case UIA_MenuControlTypeId: return L"Menu";
        case UIA_MenuBarControlTypeId: return L"MenuBar";
        case UIA_MenuItemControlTypeId: return L"MenuItem";
        case UIA_PaneControlTypeId: return L"Pane";
        case UIA_ProgressBarControlTypeId: return L"ProgressBar";
        case UIA_RadioButtonControlTypeId: return L"RadioButton";
        case UIA_ScrollBarControlTypeId: return L"ScrollBar";
        case UIA_SemanticZoomControlTypeId: return L"SemanticZoom";
        case UIA_SeparatorControlTypeId: return L"Separator";
        case UIA_SliderControlTypeId: return L"Slider";
        case UIA_SpinnerControlTypeId: return L"Spinner";
        case UIA_SplitButtonControlTypeId: return L"SplitButton";
        case UIA_StatusBarControlTypeId: return L"StatusBar";
        case UIA_TabControlTypeId: return L"Tab";
        case UIA_TabItemControlTypeId: return L"TabItem";
        case UIA_TableControlTypeId: return L"Table";
        case UIA_TextControlTypeId: return L"Text";
        case UIA_ThumbControlTypeId: return L"Thumb";
        case UIA_TitleBarControlTypeId: return L"TitleBar";
        case UIA_ToolBarControlTypeId: return L"ToolBar";
        case UIA_ToolTipControlTypeId: return L"ToolTip";
        case UIA_TreeControlTypeId: return L"Tree";
        case UIA_TreeItemControlTypeId: return L"TreeItem";
        case UIA_WindowControlTypeId: return L"Window";
        default:
            return L"ControlType_" + std::to_wstring(controlType);
    }
}

bool ReadElementInfo(IUIAutomationElement* element, UiaElementInfo& info, std::wstring& error) {
    if (!element) {
        error = L"UI Automation returned a null element.";
        return false;
    }

    BSTR name = nullptr;
    HRESULT hr = element->get_CurrentName(&name);
    if (FAILED(hr)) {
        error = L"get_CurrentName failed: " + HResultMessage(hr);
        return false;
    }
    info.name = BstrToString(name);

    CONTROLTYPEID controlType = 0;
    hr = element->get_CurrentControlType(&controlType);
    if (FAILED(hr)) {
        error = L"get_CurrentControlType failed: " + HResultMessage(hr);
        return false;
    }
    info.controlType = ControlTypeName(controlType);

    BSTR automationId = nullptr;
    hr = element->get_CurrentAutomationId(&automationId);
    if (FAILED(hr)) {
        error = L"get_CurrentAutomationId failed: " + HResultMessage(hr);
        return false;
    }
    info.automationId = BstrToString(automationId);

    BSTR className = nullptr;
    hr = element->get_CurrentClassName(&className);
    if (FAILED(hr)) {
        error = L"get_CurrentClassName failed: " + HResultMessage(hr);
        return false;
    }
    info.className = BstrToString(className);

    if (info.name.empty() && controlType == UIA_EditControlTypeId) {
        IUnknown* unknown = nullptr;
        HRESULT patternHr = element->GetCurrentPattern(UIA_ValuePatternId, &unknown);
        if (SUCCEEDED(patternHr) && unknown) {
            IUIAutomationValuePattern* value = nullptr;
            patternHr = unknown->QueryInterface(IID_PPV_ARGS(&value));
            SafeRelease(unknown);
            if (SUCCEEDED(patternHr) && value) {
                BSTR currentValue = nullptr;
                if (SUCCEEDED(value->get_CurrentValue(&currentValue))) {
                    info.value = BstrToString(currentValue);
                    info.name = info.value;
                }
                SafeRelease(value);
            }
        }
        if (info.name.empty()) {
            info.name = L"Input";
        }
    }

    if (controlType == UIA_EditControlTypeId && info.value.empty()) {
        IUnknown* unknown = nullptr;
        HRESULT patternHr = element->GetCurrentPattern(UIA_ValuePatternId, &unknown);
        if (SUCCEEDED(patternHr) && unknown) {
            IUIAutomationValuePattern* value = nullptr;
            patternHr = unknown->QueryInterface(IID_PPV_ARGS(&value));
            SafeRelease(unknown);
            if (SUCCEEDED(patternHr) && value) {
                BSTR currentValue = nullptr;
                if (SUCCEEDED(value->get_CurrentValue(&currentValue))) {
                    info.value = BstrToString(currentValue);
                }
                SafeRelease(value);
            }
        }
    }

    RECT rect = {};
    hr = element->get_CurrentBoundingRectangle(&rect);
    if (FAILED(hr)) {
        error = L"get_CurrentBoundingRectangle failed: " + HResultMessage(hr);
        return false;
    }
    info.rect = rect;

    BOOL enabled = FALSE;
    hr = element->get_CurrentIsEnabled(&enabled);
    if (FAILED(hr)) {
        error = L"get_CurrentIsEnabled failed: " + HResultMessage(hr);
        return false;
    }
    info.enabled = enabled != FALSE;

    BOOL offscreen = FALSE;
    hr = element->get_CurrentIsOffscreen(&offscreen);
    if (FAILED(hr)) {
        error = L"get_CurrentIsOffscreen failed: " + HResultMessage(hr);
        return false;
    }
    info.offscreen = offscreen != FALSE;

    return true;
}

UiaQueryResult ReadAllElements(HWND hwnd) {
    UiaQueryResult result;

    ComApartment apartment;
    if (!apartment.ok()) {
        result.errorCode = L"UIA_INIT_FAILED";
        result.errorMessage = L"CoInitializeEx failed: " + HResultMessage(apartment.hr());
        return result;
    }

    IUIAutomation* automation = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_CUIAutomation,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&automation));
    if (FAILED(hr) || !automation) {
        result.errorCode = L"UIA_INIT_FAILED";
        result.errorMessage = L"CoCreateInstance(CLSID_CUIAutomation) failed: " + HResultMessage(hr);
        return result;
    }

    IUIAutomationElement* root = nullptr;
    hr = automation->ElementFromHandle(hwnd, &root);
    if (FAILED(hr) || !root) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"ElementFromHandle failed: " + HResultMessage(hr);
        SafeRelease(automation);
        return result;
    }

    std::wstring readError;
    UiaElementInfo rootInfo;
    if (ReadElementInfo(root, rootInfo, readError)) {
        result.elements.push_back(rootInfo);
    }

    IUIAutomationCondition* trueCondition = nullptr;
    hr = automation->CreateTrueCondition(&trueCondition);
    if (FAILED(hr) || !trueCondition) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"CreateTrueCondition failed: " + HResultMessage(hr);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    IUIAutomationElementArray* descendants = nullptr;
    hr = root->FindAll(TreeScope_Subtree, trueCondition, &descendants);
    if (FAILED(hr) || !descendants) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"FindAll(TreeScope_Subtree) failed: " + HResultMessage(hr);
        SafeRelease(trueCondition);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    int length = 0;
    hr = descendants->get_Length(&length);
    if (FAILED(hr)) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"IUIAutomationElementArray::get_Length failed: " + HResultMessage(hr);
        SafeRelease(descendants);
        SafeRelease(trueCondition);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    for (int i = 0; i < length; ++i) {
        IUIAutomationElement* element = nullptr;
        hr = descendants->GetElement(i, &element);
        if (FAILED(hr) || !element) {
            continue;
        }

        UiaElementInfo info;
        if (ReadElementInfo(element, info, readError)) {
            result.elements.push_back(info);
        }
        SafeRelease(element);
    }

    SafeRelease(descendants);
    SafeRelease(trueCondition);
    SafeRelease(root);
    SafeRelease(automation);

    result.ok = true;
    return result;
}

bool NameMatches(const std::wstring& candidate, const std::wstring& query) {
    return candidate == query || candidate.find(query) != std::wstring::npos;
}

UiaPatternActionResult WithUniqueElement(
    HWND hwnd,
    const std::wstring& name,
    const std::function<HRESULT(IUIAutomationElement*, UiaPatternActionResult&)>& action) {
    UiaPatternActionResult result;

    ComApartment apartment;
    if (!apartment.ok()) {
        result.errorCode = L"UIA_INIT_FAILED";
        result.errorMessage = L"CoInitializeEx failed: " + HResultMessage(apartment.hr());
        return result;
    }

    IUIAutomation* automation = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_CUIAutomation,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&automation));
    if (FAILED(hr) || !automation) {
        result.errorCode = L"UIA_INIT_FAILED";
        result.errorMessage = L"CoCreateInstance(CLSID_CUIAutomation) failed: " + HResultMessage(hr);
        return result;
    }

    IUIAutomationElement* root = nullptr;
    hr = automation->ElementFromHandle(hwnd, &root);
    if (FAILED(hr) || !root) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"ElementFromHandle failed: " + HResultMessage(hr);
        SafeRelease(automation);
        return result;
    }

    IUIAutomationCondition* trueCondition = nullptr;
    hr = automation->CreateTrueCondition(&trueCondition);
    if (FAILED(hr) || !trueCondition) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"CreateTrueCondition failed: " + HResultMessage(hr);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    IUIAutomationElementArray* descendants = nullptr;
    hr = root->FindAll(TreeScope_Subtree, trueCondition, &descendants);
    if (FAILED(hr) || !descendants) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"FindAll(TreeScope_Subtree) failed: " + HResultMessage(hr);
        SafeRelease(trueCondition);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    int length = 0;
    hr = descendants->get_Length(&length);
    if (FAILED(hr)) {
        result.errorCode = L"UIA_TREE_FAILED";
        result.errorMessage = L"IUIAutomationElementArray::get_Length failed: " + HResultMessage(hr);
        SafeRelease(descendants);
        SafeRelease(trueCondition);
        SafeRelease(root);
        SafeRelease(automation);
        return result;
    }

    IUIAutomationElement* match = nullptr;
    int matchCount = 0;
    std::wstring readError;
    for (int i = 0; i < length; ++i) {
        IUIAutomationElement* element = nullptr;
        hr = descendants->GetElement(i, &element);
        if (FAILED(hr) || !element) {
            continue;
        }

        UiaElementInfo info;
        if (ReadElementInfo(element, info, readError) && NameMatches(info.name, name)) {
            ++matchCount;
            if (matchCount == 1) {
                match = element;
                match->AddRef();
                result.element = info;
            }
        }
        SafeRelease(element);
    }

    if (matchCount == 0) {
        result.errorCode = L"UIA_ELEMENT_NOT_FOUND";
        result.errorMessage = L"No UI Automation element matched the requested name.";
    } else if (matchCount > 1) {
        result.errorCode = L"UIA_ELEMENT_NOT_UNIQUE";
        result.errorMessage = L"UI Automation element name matched multiple elements.";
    } else {
        result.found = true;
        hr = action(match, result);
        if (FAILED(hr) && result.errorCode.empty()) {
            result.errorCode = L"UNKNOWN_ERROR";
            result.errorMessage = L"UI Automation action failed: " + HResultMessage(hr);
        }
    }

    SafeRelease(match);
    SafeRelease(descendants);
    SafeRelease(trueCondition);
    SafeRelease(root);
    SafeRelease(automation);
    return result;
}

}  // namespace

UiaQueryResult ReadUiaTree(HWND hwnd) {
    return ReadAllElements(hwnd);
}

UiaQueryResult FindUiaElementsByName(HWND hwnd, const std::wstring& name) {
    UiaQueryResult result = ReadAllElements(hwnd);
    if (!result.ok) {
        return result;
    }

    std::vector<UiaElementInfo> matches;
    for (const UiaElementInfo& element : result.elements) {
        if (NameMatches(element.name, name)) {
            matches.push_back(element);
        }
    }

    result.elements = matches;
    if (matches.empty()) {
        result.ok = false;
        result.errorCode = L"UIA_ELEMENT_NOT_FOUND";
        result.errorMessage = L"No UI Automation element matched the requested name.";
        return result;
    }
    if (matches.size() > 1) {
        result.ok = false;
        result.errorCode = L"UIA_ELEMENT_NOT_UNIQUE";
        result.errorMessage = L"UI Automation element name matched multiple elements.";
        return result;
    }

    result.ok = true;
    return result;
}

UiaPatternActionResult InvokeUiaElementByName(HWND hwnd, const std::wstring& name) {
    return WithUniqueElement(hwnd, name, [](IUIAutomationElement* element, UiaPatternActionResult& result) -> HRESULT {
        IUnknown* unknown = nullptr;
        HRESULT hr = element->GetCurrentPattern(UIA_InvokePatternId, &unknown);
        if (hr == UIA_E_ELEMENTNOTAVAILABLE || hr == UIA_E_ELEMENTNOTENABLED || hr == UIA_E_INVALIDOPERATION || FAILED(hr) || !unknown) {
            result.patternAvailable = false;
            result.ok = false;
            return S_OK;
        }

        IUIAutomationInvokePattern* invoke = nullptr;
        hr = unknown->QueryInterface(IID_PPV_ARGS(&invoke));
        SafeRelease(unknown);
        if (FAILED(hr) || !invoke) {
            result.patternAvailable = false;
            result.ok = false;
            return S_OK;
        }

        result.patternAvailable = true;
        hr = invoke->Invoke();
        SafeRelease(invoke);
        if (FAILED(hr)) {
            result.ok = false;
            result.errorCode = L"UNKNOWN_ERROR";
            result.errorMessage = L"InvokePattern.Invoke failed: " + HResultMessage(hr);
            return hr;
        }

        result.ok = true;
        return S_OK;
    });
}

UiaPatternActionResult SetUiaElementValueByName(HWND hwnd, const std::wstring& name, const std::wstring& text) {
    return WithUniqueElement(hwnd, name, [&text](IUIAutomationElement* element, UiaPatternActionResult& result) -> HRESULT {
        IUnknown* unknown = nullptr;
        HRESULT hr = element->GetCurrentPattern(UIA_ValuePatternId, &unknown);
        if (hr == UIA_E_ELEMENTNOTAVAILABLE || hr == UIA_E_ELEMENTNOTENABLED || hr == UIA_E_INVALIDOPERATION || FAILED(hr) || !unknown) {
            result.patternAvailable = false;
            result.ok = false;
            return S_OK;
        }

        IUIAutomationValuePattern* value = nullptr;
        hr = unknown->QueryInterface(IID_PPV_ARGS(&value));
        SafeRelease(unknown);
        if (FAILED(hr) || !value) {
            result.patternAvailable = false;
            result.ok = false;
            return S_OK;
        }

        BOOL readOnly = FALSE;
        value->get_CurrentIsReadOnly(&readOnly);
        if (readOnly) {
            result.patternAvailable = true;
            result.ok = false;
            result.errorCode = L"INVALID_ARGUMENT";
            result.errorMessage = L"ValuePattern is read-only.";
            SafeRelease(value);
            return E_FAIL;
        }

        BSTR bstr = SysAllocStringLen(text.data(), static_cast<UINT>(text.size()));
        hr = value->SetValue(bstr);
        SysFreeString(bstr);
        SafeRelease(value);
        result.patternAvailable = true;
        if (FAILED(hr)) {
            result.ok = false;
            result.errorCode = L"UNKNOWN_ERROR";
            result.errorMessage = L"ValuePattern.SetValue failed: " + HResultMessage(hr);
            return hr;
        }

        result.ok = true;
        return S_OK;
    });
}
