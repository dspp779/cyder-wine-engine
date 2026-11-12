#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>
#ifdef STATIC_IMPORT
__declspec(dllimport) int __cdecl PocIdentity(void);
#endif
static void json_string(const WCHAR *value)
{
    char text[8192];
    int n=WideCharToMultiByte(CP_UTF8,0,value,-1,text,sizeof(text),NULL,NULL);
    putchar('"');
    for (int i=0;n>0 && i<n-1;i++) {
        unsigned char c=(unsigned char)text[i];
        if(c=='"' || c=='\\') { putchar('\\');putchar(c); }
        else if(c<32) printf("\\u%04x",c);
        else putchar(c);
    }
    putchar('"');
}
static int inspect(const WCHAR *request,const char *kind,HMODULE provided)
{
    HMODULE module=provided ? provided : LoadLibraryW(request);
    DWORD error=module ? 0 : GetLastError();
    FILETIME created,exited,kernel,user;
    ULARGE_INTEGER birth={0};
    if(GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user)) {
        birth.LowPart=created.dwLowDateTime;birth.HighPart=created.dwHighDateTime;
    }
    printf("{\"kind\":\"%s\",\"pid\":%lu,\"creation100ns\":%llu,\"loaded\":%s,\"error\":%lu,\"request\":",
           kind,(unsigned long)GetCurrentProcessId(),(unsigned long long)birth.QuadPart,
           module ? "true" : "false",(unsigned long)error);
    json_string(request);
    if(module) {
        WCHAR path[4096]={0};
        typedef int (__cdecl *identity_fn)(void);
        identity_fn identity=(identity_fn)(void *)GetProcAddress(module,"PocIdentity");
        GetModuleFileNameW(module,path,4096);
        printf(",\"modulePath\":");json_string(path);
        printf(",\"id\":%d,\"builtinMarker\":%s,\"directDrawCreate\":%s,\"header96\":\"",
               identity ? identity() : -1,
               !memcmp((unsigned char *)module+64,"Wine builtin DLL",16) ? "true" : "false",
               GetProcAddress(module,"DirectDrawCreate") ? "true" : "false");
        for(int i=0;i<96;i++)printf("%02x",((unsigned char *)module)[i]);
        printf("\"");
    }
    printf("}\n");fflush(stdout);
    if(module && !provided)FreeLibrary(module);
    return module ? 0 : 1;
}
static int spawn(int drop)
{
    WCHAR self[4096],command[4200],*environment=NULL,*block=NULL;
    STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};
    GetModuleFileNameW(NULL,self,4096);
    swprintf(command,4200,L"\"%ls\" --child",self);
    if(drop) {
        const WCHAR *entry;
        SIZE_T size=2;
        block=GetEnvironmentStringsW();
        if(!block)return 71;
        for(entry=block;*entry;entry+=wcslen(entry)+1)size+=wcslen(entry)+1;
        environment=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,size*sizeof(WCHAR));
        if(!environment){FreeEnvironmentStringsW(block);return 72;}
        WCHAR *out=environment;
        for(entry=block;*entry;entry+=wcslen(entry)+1) {
            if(!wcsnicmp(entry,L"CYDER_DDRAW_PATH=",17))continue;
            SIZE_T len=wcslen(entry)+1;memcpy(out,entry,len*sizeof(WCHAR));out+=len;
        }
        *out=0;
    }
    si.cb=sizeof(si);si.dwFlags=STARTF_USESTDHANDLES;
    si.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);si.hStdError=GetStdHandle(STD_ERROR_HANDLE);
    BOOL ok=CreateProcessW(self,command,NULL,NULL,TRUE,CREATE_UNICODE_ENVIRONMENT,environment,NULL,&si,&pi);
    if(environment)HeapFree(GetProcessHeap(),0,environment);
    if(block)FreeEnvironmentStringsW(block);
    if(!ok){printf("{\"kind\":\"spawn-failed\",\"error\":%lu}\n",(unsigned long)GetLastError());return 73;}
    CloseHandle(pi.hThread);
    DWORD wait=WaitForSingleObject(pi.hProcess,15000),code=74;
    if(wait==WAIT_OBJECT_0)GetExitCodeProcess(pi.hProcess,&code);
    CloseHandle(pi.hProcess);return (int)code;
}
int wmain(int argc,WCHAR **argv)
{
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX|SEM_NOOPENFILEERRORBOX);
#ifdef STATIC_IMPORT
    if(PocIdentity()<0)return 75;
    int status=inspect(L"ddraw.dll","static",GetModuleHandleW(L"ddraw.dll"));
#else
    const WCHAR *request=(argc>2 && !wcscmp(argv[1],L"--absolute")) ? argv[2] : L"ddraw.dll";
    if(argc>1 && !wcscmp(argv[1],L"--alias"))request=L"DdRaW";
    int status=inspect(request,"dynamic",NULL);
#endif
    if(argc>1 && !wcscmp(argv[1],L"--spawn-inherit"))return status ? status : spawn(0);
    if(argc>1 && !wcscmp(argv[1],L"--spawn-drop"))return status ? status : spawn(1);
    if(argc>1 && !wcscmp(argv[1],L"--hold"))Sleep(4000);
    return status;
}
