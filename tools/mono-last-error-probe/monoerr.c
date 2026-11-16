/* monoerr: does Unity Mono see the right Win32 last error under Wine?
 *
 * Loads the game's own Mono (mono-2.0-bdwgc.dll) and mscorlib, then:
 *   1. native:  FindFirstFile/FindNextFile to the end -> GetLastError (expect 18)
 *   2. native:  GetFileAttributesW(missing)            -> GetLastError (expect 2)
 *   3. managed: File.Exists(missing)                   (expect False)
 *   4. managed: Directory.GetFiles(existing dir)       (expect no exception)
 *   5. managed: Marshal.GetLastWin32Error after (3)
 *   6. host TSD slot %gs:0x68 is unchanged by Mono (it holds the macOS gmtime
 *      buffer pointer on macOS; Mono must not write the last error there)
 *
 * usage: monoerr.exe <game-root-windows-path> <existing-dir> <missing-file>
 */
#include <windows.h>
#include <stdio.h>

typedef void *(*fn_ptr)();
static HMODULE mono;
#define F(name) ((fn_ptr)GetProcAddress(mono, #name))

static void *invoke(void *method, void **args, const char *label)
{
    void *exc = NULL, *res;
    res = ((void *(*)(void *, void *, void **, void **))F(mono_runtime_invoke))(method, NULL, args, &exc);
    if (exc)
    {
        void *str = ((void *(*)(void *, void **))F(mono_object_to_string))(exc, NULL);
        char *utf8 = ((char *(*)(void *))F(mono_string_to_utf8))(str);
        printf("%s: EXCEPTION %.300s\n", label, utf8);
        return NULL;
    }
    return res;
}

int main(int argc, char **argv)
{
    char path[MAX_PATH * 2];
    WIN32_FIND_DATAA fd;
    HANDLE h;
    DWORD err;
    void *domain, *image, *klass, *m, *s, *r, *args[1];

    unsigned long long gs68_before, gs68_after;

    if (argc < 4) { printf("usage: monoerr <game-root> <existing-dir> <missing-file>\n"); return 2; }
    __asm__ volatile ("movq %%gs:0x68, %0" : "=r" (gs68_before));

    /* 1. native enumeration */
    snprintf(path, sizeof(path), "%s\\*", argv[2]);
    h = FindFirstFileA(path, &fd);
    if (h == INVALID_HANDLE_VALUE) { printf("native FindFirstFile failed %lu\n", GetLastError()); return 1; }
    while (FindNextFileA(h, &fd)) ;
    err = GetLastError();
    FindClose(h);
    printf("native FindNextFile end: GetLastError=%lu (expect 18)\n", err);

    /* 2. native attributes of missing file */
    SetLastError(0xdeadbeef);
    if (GetFileAttributesA(argv[3]) == INVALID_FILE_ATTRIBUTES) err = GetLastError(); else err = 0xffffffff;
    printf("native GetFileAttributes(missing): GetLastError=%lu (expect 2 or 3)\n", err);

    /* load the game's Mono */
    snprintf(path, sizeof(path), "%s\\MonoBleedingEdge\\EmbedRuntime\\mono-2.0-bdwgc.dll", argv[1]);
    if (!(mono = LoadLibraryA(path))) { printf("LoadLibrary mono failed %lu\n", GetLastError()); return 1; }
    snprintf(path, sizeof(path), "%s\\Cities2_Data\\Managed", argv[1]);
    ((void (*)(const char *))F(mono_set_assemblies_path))(path);
    {
        char etc[MAX_PATH * 2];
        snprintf(etc, sizeof(etc), "%s\\MonoBleedingEdge\\etc", argv[1]);
        ((void (*)(const char *, const char *))F(mono_set_dirs))(path, etc);
    }
    domain = ((void *(*)(const char *, const char *))F(mono_jit_init_version))("monoerr", "v4.0.30319");
    if (!domain) { printf("mono_jit_init failed\n"); return 1; }
    image = ((void *(*)(void))F(mono_get_corlib))();
    image = ((void *(*)(void *))F(mono_assembly_get_image))(((void *(*)(void *))F(mono_image_get_assembly))(image));

    /* 3. File.Exists(missing) */
    klass = ((void *(*)(void *, const char *, const char *))F(mono_class_from_name))(image, "System.IO", "File");
    m = ((void *(*)(void *, const char *, int))F(mono_class_get_method_from_name))(klass, "Exists", 1);
    s = ((void *(*)(void *, const char *))F(mono_string_new))(domain, argv[3]);
    args[0] = s;
    r = invoke(m, args, "managed File.Exists(missing)");
    if (r) printf("managed File.Exists(missing) = %s (expect False)\n",
                  *(unsigned char *)((void *(*)(void *))F(mono_object_unbox))(r) ? "True" : "False");

    /* 5. Marshal.GetLastWin32Error */
    klass = ((void *(*)(void *, const char *, const char *))F(mono_class_from_name))(image, "System.Runtime.InteropServices", "Marshal");
    m = ((void *(*)(void *, const char *, int))F(mono_class_get_method_from_name))(klass, "GetLastWin32Error", 0);
    r = invoke(m, NULL, "Marshal.GetLastWin32Error");
    if (r) printf("managed Marshal.GetLastWin32Error after File.Exists = %d\n",
                  *(int *)((void *(*)(void *))F(mono_object_unbox))(r));

    /* 4. Directory.GetFiles(existing) */
    klass = ((void *(*)(void *, const char *, const char *))F(mono_class_from_name))(image, "System.IO", "Directory");
    m = ((void *(*)(void *, const char *, int))F(mono_class_get_method_from_name))(klass, "GetFiles", 1);
    args[0] = ((void *(*)(void *, const char *))F(mono_string_new))(domain, argv[2]);
    r = invoke(m, args, "managed Directory.GetFiles(existing)");
    if (r) printf("managed Directory.GetFiles(existing) = OK (%d files)\n",
                  (int)((unsigned long long (*)(void *))F(mono_array_length))(r));
    __asm__ volatile ("movq %%gs:0x68, %0" : "=r" (gs68_after));
    printf("%%gs:0x68 before=%#llx after=%#llx %s\n", gs68_before, gs68_after,
           gs68_before == gs68_after ? "(unchanged)" : "(CHANGED)");
    fflush(stdout);
    return 0;
}
