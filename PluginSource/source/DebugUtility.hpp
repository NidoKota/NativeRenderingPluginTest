// #pragma once

#include <iostream>
#include <vector>
#include <string>
#include <sstream>

void (*g_logCallback)(const char*);
void (*g_logErrorCallback)(const char*);
std::vector<char> g_logStrBuffer;

inline void LogInternal(const std::string& message, void (*callback)(const char*))
{
    if (!callback)
    {
        return;
    }
    
    if (message.empty())
    {
        callback(nullptr);
    }
    else
    {
        size_t size = message.length() + 1;
        g_logStrBuffer.resize(size);
        strncpy(g_logStrBuffer.data(), message.c_str(), size);
        callback(g_logStrBuffer.data());
    }
}

inline void Log(const std::string& message)
{
    LogInternal(message, g_logCallback);
}

inline void LogError(const std::string& message)
{
    LogInternal(message, g_logErrorCallback);
}

#define SS2STR(x) \
([&]() -> std::string { std::stringstream ss; ss << std::boolalpha << x; return ss.str(); })()

#define LOG_STR \
"\n(at <a href=""{" << __FILE__ << "}"" line=""{" << __LINE__ << "}"">" << __FILE__ << ":" << __LINE__ << "</a>)"

#define FILE_LINE_STR \
__FILE__ << ":" << std::setw(3) << std::setfill('0') << __LINE__ << std::setfill(' ')

#define LOG(x) \
do { Log(SS2STR(x << LOG_STR << "\n")); } while (false)

#define LOGERR(x) \
do { LogError(SS2STR(x << LOG_STR << "\n")); } while (false)
