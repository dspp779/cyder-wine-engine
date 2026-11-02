#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL level = 0;
    D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
    HRESULT result = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, levels, 3,
                                     D3D11_SDK_VERSION, &device, &level, &context);
    printf("D3D11CreateDevice HRESULT=0x%08lx feature_level=0x%x\n", (unsigned long)result, level);
    if (FAILED(result)) return 1;
    if (argc > 1 && !strcmp(argv[1], "--require-winemetal"))
    {
        HMODULE metal = GetModuleHandleA("winemetal.dll");
        char path[MAX_PATH] = {0};
        if (metal) GetModuleFileNameA(metal, path, sizeof(path));
        printf("winemetal loaded=%s path=%s\n", metal ? "yes" : "no", path);
        fflush(stdout);
        if (!metal)
        {
            ID3D11DeviceContext_Release(context);
            ID3D11Device_Release(device);
            return 2;
        }
        Sleep(5000); /* permit a process-scoped native module observation */
    }
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    return 0;
}
