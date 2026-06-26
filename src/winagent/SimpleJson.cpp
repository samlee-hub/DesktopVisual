#include "SimpleJson.h"

#include <cwctype>
#include <sstream>

namespace simplejson {
namespace {

class Parser {
public:
    explicit Parser(const std::wstring& text) : text_(text) {}

    ParseResult ParseRoot() {
        ParseResult result;
        SkipWs();
        Value root;
        if (!ParseValue(root)) {
            result.error = error_.empty() ? L"invalid JSON" : error_;
            return result;
        }
        SkipWs();
        if (pos_ != text_.size()) {
            result.error = L"trailing characters after JSON value";
            return result;
        }
        result.ok = true;
        result.root = root;
        return result;
    }

private:
    const std::wstring& text_;
    size_t pos_ = 0;
    std::wstring error_;

    void SkipWs() {
        while (pos_ < text_.size() && (std::iswspace(text_[pos_]) || text_[pos_] == 0xfeff)) ++pos_;
    }

    bool Match(const std::wstring& token) {
        if (text_.compare(pos_, token.size(), token) != 0) return false;
        pos_ += token.size();
        return true;
    }

    bool ParseValue(Value& out) {
        SkipWs();
        if (pos_ >= text_.size()) {
            error_ = L"unexpected end of JSON";
            return false;
        }
        wchar_t ch = text_[pos_];
        if (ch == L'{') return ParseObject(out);
        if (ch == L'[') return ParseArray(out);
        if (ch == L'"') {
            std::wstring value;
            if (!ParseString(value)) return false;
            out.type = Type::String;
            out.stringValue = value;
            return true;
        }
        if (ch == L't' && Match(L"true")) {
            out.type = Type::Bool;
            out.boolValue = true;
            return true;
        }
        if (ch == L'f' && Match(L"false")) {
            out.type = Type::Bool;
            out.boolValue = false;
            return true;
        }
        if (ch == L'n' && Match(L"null")) {
            out.type = Type::Null;
            return true;
        }
        if (ch == L'-' || (ch >= L'0' && ch <= L'9')) {
            return ParseNumber(out);
        }
        error_ = L"unexpected JSON token";
        return false;
    }

    bool ParseObject(Value& out) {
        if (text_[pos_] != L'{') return false;
        ++pos_;
        out.type = Type::Object;
        out.objectValue.clear();
        SkipWs();
        if (pos_ < text_.size() && text_[pos_] == L'}') {
            ++pos_;
            return true;
        }
        while (pos_ < text_.size()) {
            SkipWs();
            std::wstring key;
            if (!ParseString(key)) return false;
            SkipWs();
            if (pos_ >= text_.size() || text_[pos_] != L':') {
                error_ = L"expected ':' after object key";
                return false;
            }
            ++pos_;
            Value value;
            if (!ParseValue(value)) return false;
            out.objectValue[key] = value;
            SkipWs();
            if (pos_ < text_.size() && text_[pos_] == L',') {
                ++pos_;
                continue;
            }
            if (pos_ < text_.size() && text_[pos_] == L'}') {
                ++pos_;
                return true;
            }
            error_ = L"expected ',' or '}' in object";
            return false;
        }
        error_ = L"unterminated JSON object";
        return false;
    }

    bool ParseArray(Value& out) {
        if (text_[pos_] != L'[') return false;
        ++pos_;
        out.type = Type::Array;
        out.arrayValue.clear();
        SkipWs();
        if (pos_ < text_.size() && text_[pos_] == L']') {
            ++pos_;
            return true;
        }
        while (pos_ < text_.size()) {
            Value value;
            if (!ParseValue(value)) return false;
            out.arrayValue.push_back(value);
            SkipWs();
            if (pos_ < text_.size() && text_[pos_] == L',') {
                ++pos_;
                continue;
            }
            if (pos_ < text_.size() && text_[pos_] == L']') {
                ++pos_;
                return true;
            }
            error_ = L"expected ',' or ']' in array";
            return false;
        }
        error_ = L"unterminated JSON array";
        return false;
    }

    int HexValue(wchar_t ch) {
        if (ch >= L'0' && ch <= L'9') return ch - L'0';
        if (ch >= L'a' && ch <= L'f') return 10 + ch - L'a';
        if (ch >= L'A' && ch <= L'F') return 10 + ch - L'A';
        return -1;
    }

    bool ParseString(std::wstring& out) {
        SkipWs();
        if (pos_ >= text_.size() || text_[pos_] != L'"') {
            error_ = L"expected JSON string";
            return false;
        }
        ++pos_;
        out.clear();
        while (pos_ < text_.size()) {
            wchar_t ch = text_[pos_++];
            if (ch == L'"') return true;
            if (ch != L'\\') {
                out += ch;
                continue;
            }
            if (pos_ >= text_.size()) {
                error_ = L"unterminated JSON escape";
                return false;
            }
            wchar_t esc = text_[pos_++];
            switch (esc) {
                case L'"': out += L'"'; break;
                case L'\\': out += L'\\'; break;
                case L'/': out += L'/'; break;
                case L'b': out += L'\b'; break;
                case L'f': out += L'\f'; break;
                case L'n': out += L'\n'; break;
                case L'r': out += L'\r'; break;
                case L't': out += L'\t'; break;
                case L'u': {
                    if (pos_ + 4 > text_.size()) {
                        error_ = L"incomplete JSON unicode escape";
                        return false;
                    }
                    int code = 0;
                    for (int i = 0; i < 4; ++i) {
                        int hex = HexValue(text_[pos_++]);
                        if (hex < 0) {
                            error_ = L"invalid JSON unicode escape";
                            return false;
                        }
                        code = (code << 4) | hex;
                    }
                    out += static_cast<wchar_t>(code);
                    break;
                }
                default:
                    error_ = L"invalid JSON escape";
                    return false;
            }
        }
        error_ = L"unterminated JSON string";
        return false;
    }

    bool ParseNumber(Value& out) {
        size_t start = pos_;
        if (text_[pos_] == L'-') ++pos_;
        while (pos_ < text_.size() && text_[pos_] >= L'0' && text_[pos_] <= L'9') ++pos_;
        if (pos_ < text_.size() && text_[pos_] == L'.') {
            ++pos_;
            while (pos_ < text_.size() && text_[pos_] >= L'0' && text_[pos_] <= L'9') ++pos_;
        }
        if (pos_ < text_.size() && (text_[pos_] == L'e' || text_[pos_] == L'E')) {
            ++pos_;
            if (pos_ < text_.size() && (text_[pos_] == L'+' || text_[pos_] == L'-')) ++pos_;
            while (pos_ < text_.size() && text_[pos_] >= L'0' && text_[pos_] <= L'9') ++pos_;
        }
        try {
            out.type = Type::Number;
            out.numberValue = std::stod(text_.substr(start, pos_ - start));
            return true;
        } catch (...) {
            error_ = L"invalid JSON number";
            return false;
        }
    }
};

}  // namespace

ParseResult Parse(const std::wstring& text) {
    Parser parser(text);
    return parser.ParseRoot();
}

const Value* Find(const Value& object, const std::wstring& key) {
    if (!object.IsObject()) return nullptr;
    auto it = object.objectValue.find(key);
    if (it == object.objectValue.end()) return nullptr;
    return &it->second;
}

bool Has(const Value& object, const std::wstring& key) {
    return Find(object, key) != nullptr;
}

std::wstring GetString(const Value& object, const std::wstring& key, const std::wstring& def) {
    const Value* value = Find(object, key);
    if (!value || !value->IsString()) return def;
    return value->stringValue;
}

bool GetBool(const Value& object, const std::wstring& key, bool def) {
    const Value* value = Find(object, key);
    if (!value || !value->IsBool()) return def;
    return value->boolValue;
}

int GetInt(const Value& object, const std::wstring& key, int def) {
    const Value* value = Find(object, key);
    if (!value || !value->IsNumber()) return def;
    return static_cast<int>(value->numberValue);
}

std::vector<std::wstring> GetStringArray(const Value& object, const std::wstring& key) {
    std::vector<std::wstring> values;
    const Value* array = Find(object, key);
    if (!array || !array->IsArray()) return values;
    for (const Value& item : array->arrayValue) {
        if (item.IsString()) values.push_back(item.stringValue);
    }
    return values;
}

std::wstring Quote(const std::wstring& value) {
    std::wstring escaped;
    for (wchar_t ch : value) {
        switch (ch) {
            case L'\\': escaped += L"\\\\"; break;
            case L'"': escaped += L"\\\""; break;
            case L'\n': escaped += L"\\n"; break;
            case L'\r': escaped += L"\\r"; break;
            case L'\t': escaped += L"\\t"; break;
            default:
                if (ch < 0x20 || ch > 0x7e) {
                    std::wstringstream stream;
                    stream << L"\\u" << std::hex;
                    stream.width(4);
                    stream.fill(L'0');
                    stream << static_cast<int>(ch);
                    escaped += stream.str();
                } else {
                    escaped += ch;
                }
                break;
        }
    }
    return L"\"" + escaped + L"\"";
}

std::wstring Bool(bool value) {
    return value ? L"true" : L"false";
}

}  // namespace simplejson
