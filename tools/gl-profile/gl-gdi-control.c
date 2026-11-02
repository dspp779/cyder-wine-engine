/* Manual visible control: GL red -> GDI green -> recreated GL blue, 10 s each.
 * Completion alone does not validate pixels; capture and inspect each phase. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
static int phase;
static HGLRC context;
static HDC dc;
static void gl_color(float r,float g,float b) {
 glClearColor(r,g,b,1);glClear(GL_COLOR_BUFFER_BIT);SwapBuffers(dc);
}
static LRESULT CALLBACK proc(HWND w,UINT msg,WPARAM wp,LPARAM lp) {
 if(msg==WM_PAINT) {
  PAINTSTRUCT ps;HDC paint=BeginPaint(w,&ps);
  if(phase==1){RECT r;GetClientRect(w,&r);HBRUSH b=CreateSolidBrush(RGB(0,255,0));FillRect(paint,&r,b);DeleteObject(b);}
  EndPaint(w,&ps);return 0;
 }
 if(msg==WM_TIMER) {
  ++phase;
  if(phase==1){wglMakeCurrent(NULL,NULL);wglDeleteContext(context);context=NULL;InvalidateRect(w,NULL,FALSE);UpdateWindow(w);puts("PHASE GDI_GREEN");fflush(stdout);}
  else if(phase==2){context=wglCreateContext(dc);wglMakeCurrent(dc,context);gl_color(0,0,1);puts("PHASE GL_BLUE");fflush(stdout);}
  else {DestroyWindow(w);}
  return 0;
 }
 if(msg==WM_DESTROY){if(context){wglMakeCurrent(NULL,NULL);wglDeleteContext(context);}ReleaseDC(w,dc);PostQuitMessage(0);return 0;}
 return DefWindowProcW(w,msg,wp,lp);
}
int main(void) {
 WNDCLASSW c={0};c.style=CS_OWNDC;c.lpfnWndProc=proc;c.hInstance=GetModuleHandleW(NULL);c.lpszClassName=L"CyderHybridControl";RegisterClassW(&c);
 HWND w=CreateWindowW(c.lpszClassName,L"Cyder GL-GDI Control",WS_OVERLAPPEDWINDOW|WS_VISIBLE,1040,150,360,300,NULL,NULL,c.hInstance,NULL);
 if(!w)return 2;dc=GetDC(w);
 PIXELFORMATDESCRIPTOR p={0};p.nSize=sizeof(p);p.nVersion=1;p.dwFlags=PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER;p.iPixelType=PFD_TYPE_RGBA;p.cColorBits=24;
 int format=ChoosePixelFormat(dc,&p);if(!format||!SetPixelFormat(dc,format,&p))return 3;
 context=wglCreateContext(dc);if(!context||!wglMakeCurrent(dc,context))return 4;
 gl_color(1,0,0);puts("PHASE GL_RED");fflush(stdout);SetTimer(w,1,10000,NULL);
 MSG m;while(GetMessageW(&m,NULL,0,0)>0){TranslateMessage(&m);DispatchMessageW(&m);}puts("Hybrid control completed; verify the three visible colors");return 0;
}
