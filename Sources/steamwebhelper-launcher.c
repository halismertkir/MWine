/* M Wine: a local CEF compatibility launcher. No arguments or credentials are logged.
 * Wine/macOS CEF workaround informed by notpop/steam-on-m1-wine (MIT).
 * The Valve binary is preserved and launched unmodified.
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>
#include <stdio.h>

int wmain(void) {
    wchar_t original[32768];
    DWORD length = GetModuleFileNameW(NULL, original, 32768);
    if (!length || length >= 32768) return 1;
    wchar_t *slash = wcsrchr(original, L'\\');
    if (!slash || (slash - original) + 40 >= 32768) return 1;
    wcscpy(slash + 1, L"steamwebhelper.mwine-original.exe");
    const wchar_t *tail = GetCommandLineW();
    int quoted = 0;
    while (*tail) {
        if (*tail == L'\"') quoted = !quoted;
        else if ((*tail == L' ' || *tail == L'\t') && !quoted) break;
        ++tail;
    }
    while (*tail == L' ' || *tail == L'\t') ++tail;
    const wchar_t *flags = L"--disable-gpu --single-process";
    size_t capacity = wcslen(original) + wcslen(flags) + wcslen(tail) + 8;
    if (capacity > 32767) return 1;
    wchar_t *command = calloc(capacity, sizeof(wchar_t));
    if (!command) return 1;
    swprintf(command, capacity, L"\"%ls\" %ls %ls", original, flags, tail);
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION child = {0};
    startup.cb = sizeof(startup);
    BOOL result = CreateProcessW(original, command, NULL, NULL, FALSE, 0, NULL, NULL, &startup, &child);
    free(command);
    if (!result) return 1;
    WaitForSingleObject(child.hProcess, INFINITE);
    DWORD exitCode = 1;
    GetExitCodeProcess(child.hProcess, &exitCode);
    CloseHandle(child.hProcess);
    CloseHandle(child.hThread);
    return (int)exitCode;
}
