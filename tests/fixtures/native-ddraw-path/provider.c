#include <windows.h>
#ifndef PROVIDER_ID
#error PROVIDER_ID required
#endif
__declspec(dllexport) int __cdecl PocIdentity(void) { return PROVIDER_ID; }
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)instance; (void)reason; (void)reserved;
    return TRUE;
}
