#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
int main(void)
{
    PIXELFORMATDESCRIPTOR pfd={0};
    HWND window=CreateWindowA("STATIC","Cyder GL profile control",WS_OVERLAPPEDWINDOW,0,0,64,64,0,0,GetModuleHandleA(0),0);
    HDC dc;
    HGLRC context;
    int format;
    if (!window) return 1;
    dc=GetDC(window);
    pfd.nSize=sizeof(pfd);pfd.nVersion=1;pfd.dwFlags=PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER;
    pfd.iPixelType=PFD_TYPE_RGBA;pfd.cColorBits=24;
    format=ChoosePixelFormat(dc,&pfd);
    if (!format || !SetPixelFormat(dc,format,&pfd) || !(context=wglCreateContext(dc)) || !wglMakeCurrent(dc,context)) return 2;
    for (int i=0;i<8;++i) {glDrawBuffer(GL_FRONT);glClearColor(0,1,0,1);glClear(GL_COLOR_BUFFER_BIT);glFlush();}
    for (int i=0;i<8;++i) {glDrawBuffer(GL_BACK);glClearColor(0,0,1,1);glClear(GL_COLOR_BUFFER_BIT);if(!SwapBuffers(dc))return 3;}
    wglMakeCurrent(0,0);wglDeleteContext(context);ReleaseDC(window,dc);DestroyWindow(window);
    puts("PASS real GL front flush and back-buffer swap control");
    return 0;
}
