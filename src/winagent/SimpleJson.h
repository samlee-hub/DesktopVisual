#pragma once

#include <map>
#include <string>
#include <vector>

namespace simplejson {

enum class Type {
    Null,
    Bool,
    Number,
    String,
    Object,
    Array
};

struct Value {
    Type type = Type::Null;
    bool boolValue = false;
    double numberValue = 0.0;
    std::wstring stringValue;
    std::map<std::wstring, Value> objectValue;
    std::vector<Value> arrayValue;

    bool IsNull() const { return type == Type::Null; }
    bool IsBool() const { return type == Type::Bool; }
    bool IsNumber() const { return type == Type::Number; }
    bool IsString() const { return type == Type::String; }
    bool IsObject() const { return type == Type::Object; }
    bool IsArray() const { return type == Type::Array; }
};

struct ParseResult {
    bool ok = false;
    std::wstring error;
    Value root;
};

ParseResult Parse(const std::wstring& text);

const Value* Find(const Value& object, const std::wstring& key);
bool Has(const Value& object, const std::wstring& key);
std::wstring GetString(const Value& object, const std::wstring& key, const std::wstring& def = L"");
bool GetBool(const Value& object, const std::wstring& key, bool def = false);
int GetInt(const Value& object, const std::wstring& key, int def = 0);
std::vector<std::wstring> GetStringArray(const Value& object, const std::wstring& key);
std::wstring Quote(const std::wstring& value);
std::wstring Bool(bool value);

}  // namespace simplejson
