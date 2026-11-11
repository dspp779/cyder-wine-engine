#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const WCHAR class_name[] = L"CyderAXControl";
static const WCHAR title[] = L"Cyder AX Restore Wine Control";

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wp, LPARAM lp)
{
    switch (message)
    {
    case WM_PAINT:
    {
        PAINTSTRUCT paint;
        RECT rect;
        HDC dc = BeginPaint(window, &paint);
        HBRUSH brush = CreateSolidBrush(RGB(0, 180, 90));
        GetClientRect(window, &rect);
        FillRect(dc, &rect, brush);
        DeleteObject(brush);
        EndPaint(window, &paint);
        return 0;
    }
    case WM_SYSCOMMAND:
        printf("WIN32 SC command=%lx iconic=%d\n", (unsigned long)(wp & 0xfff0), IsIconic(window));
        fflush(stdout);
        break;
    case WM_SIZE:
        printf("WIN32 SIZE kind=%lu width=%u height=%u iconic=%d\n",
               (unsigned long)wp, LOWORD(lp), HIWORD(lp), IsIconic(window));
        fflush(stdout);
        break;
    case WM_CLOSE:
        puts("WIN32 WM_CLOSE");
        fflush(stdout);
        DestroyWindow(window);
        return 0;
    case WM_TIMER:
        puts("TIMEOUT cleanup; not a normal-close pass");
        fflush(stdout);
        DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wp, lp);
}

int main(int argc, char **argv)
{
    WNDCLASSW cls = {0};
    HWND window;
    MSG message;
    if (argc == 2 && !strcmp(argv[1], "--close"))
    {
        DWORD_PTR result;
        window = FindWindowW(class_name, title);
        if (!window) return 3;
        return SendMessageTimeoutW(window, WM_CLOSE, 0, 0, SMTO_ABORTIFHUNG, 5000, &result) ? 0 : 4;
    }
    if (argc != 1) return 2;
    cls.lpfnWndProc = window_proc;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.lpszClassName = class_name;
    if (!RegisterClassW(&cls)) return 2;
    window = CreateWindowW(class_name, title, WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                          300, 200, 640, 480, NULL, NULL, cls.hInstance, NULL);
    if (!window || !SetTimer(window, 1, 180000, NULL)) return 2;
    puts("READY Wine control");
    fflush(stdout);
    while (GetMessageW(&message, NULL, 0, 0) > 0)
    {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    puts("EXIT message loop");
    return 0;
}
