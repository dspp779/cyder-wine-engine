/* BlueCG-only experimental final-bitmap presenter. LGPL-2.1-or-later. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdint.h>
#ifndef GL_BGRA
#define GL_BGRA 0x80e1
#endif
#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE 0x812f
#endif
#ifndef GL_UNPACK_ROW_LENGTH
#define GL_UNPACK_ROW_LENGTH 0x0cf2
#endif
static struct {
 HWND parent, child; HDC dc, staging; HGLRC context; HBITMAP bitmap, previous;
 void *bits; GLuint texture, lut, program; int sw, sh, filter, dw, dh; DWORD thread; BOOL visible;
 HANDLE log; unsigned frames, errors, direct, copied; BOOL active;
} state;
static HINSTANCE instance;

#define GL_TEXTURE0 0x84c0
#define GL_TEXTURE1 0x84c1
#define GL_TEXTURE_3D 0x806f
#define GL_TEXTURE_WRAP_R 0x8072
#define GL_FRAGMENT_SHADER 0x8b30
#define GL_COMPILE_STATUS 0x8b81
#define GL_LINK_STATUS 0x8b82
static GLuint (APIENTRY *pCreateShader)(GLenum);
static void (APIENTRY *pShaderSource)(GLuint,GLsizei,const char *const*,const GLint*);
static void (APIENTRY *pCompileShader)(GLuint);
static void (APIENTRY *pGetShaderiv)(GLuint,GLenum,GLint*);
static void (APIENTRY *pGetShaderInfoLog)(GLuint,GLsizei,GLsizei*,char*);
static GLuint (APIENTRY *pCreateProgram)(void);
static void (APIENTRY *pAttachShader)(GLuint,GLuint);
static void (APIENTRY *pLinkProgram)(GLuint);
static void (APIENTRY *pGetProgramiv)(GLuint,GLenum,GLint*);
static void (APIENTRY *pUseProgram)(GLuint);
static GLint (APIENTRY *pGetUniformLocation)(GLuint,const char*);
static void (APIENTRY *pUniform1i)(GLint,GLint);
static void (APIENTRY *pDeleteShader)(GLuint);
static void (APIENTRY *pDeleteProgram)(GLuint);
static void (APIENTRY *pActiveTexture)(GLenum);
static void (APIENTRY *pTexImage3D)(GLenum,GLint,GLint,GLsizei,GLsizei,GLsizei,GLint,GLenum,GLenum,const void*);

static void log_line(const char *text)
{
 DWORD done;
 if (state.log && state.log != INVALID_HANDLE_VALUE)
  WriteFile(state.log,text,(DWORD)strlen(text),&done,NULL);
}
static void release_gpu(void)
{
 HGLRC old=wglGetCurrentContext(),owned=state.context;HDC olddc=wglGetCurrentDC();char line[160];
 if(state.context) {
  if(wglMakeCurrent(state.dc,state.context)) {
   if(state.texture)glDeleteTextures(1,&state.texture);
   if(state.lut)glDeleteTextures(1,&state.lut);
   if(state.program && pDeleteProgram)pDeleteProgram(state.program);
   state.lut=state.program=0;
   wglMakeCurrent(NULL,NULL);
  }
  wglDeleteContext(state.context);state.context=NULL;state.texture=0;
  if(old && old!=owned)wglMakeCurrent(olddc,old);
 }
 if(state.staging) {SelectObject(state.staging,state.previous);DeleteObject(state.bitmap);DeleteDC(state.staging);state.staging=NULL;state.bits=NULL;}
 if(state.dc){ReleaseDC(state.child,state.dc);state.dc=NULL;}
 snprintf(line,sizeof(line),"final frames=%u errors=%u direct=%u copied=%u\n",state.frames,state.errors,state.direct,state.copied);log_line(line);
 if(state.log && state.log!=INVALID_HANDLE_VALUE)CloseHandle(state.log);
 state.log=NULL;state.active=FALSE;state.visible=FALSE;state.sw=state.sh=0;
}
static LRESULT CALLBACK window_proc(HWND w,UINT msg,WPARAM wp,LPARAM lp)
{
 if(msg==WM_NCHITTEST)return HTTRANSPARENT;
 if(msg==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
 if(msg==WM_ERASEBKGND)return 1;
 if(msg==WM_PAINT){PAINTSTRUCT paint;BeginPaint(w,&paint);EndPaint(w,&paint);return 0;}
 if(msg==WM_DESTROY && w==state.child){release_gpu();state.child=NULL;state.parent=NULL;}
 return DefWindowProcW(w,msg,wp,lp);
}
static BOOL setup_color_lut(void)
{
 WCHAR path[MAX_PATH];HANDLE file;DWORD size,got;unsigned char *data;GLuint shader;GLint ok;
 const char *fragment="#version 120\nuniform sampler2D frame; uniform sampler3D outputLut; void main(){vec3 c=texture2D(frame,gl_TexCoord[0].st).rgb;gl_FragColor=vec4(texture3D(outputLut,c*(32.0/33.0)+vec3(0.5/33.0)).rgb,1.0);}";
 #define LOAD(name) if(!(p##name=(void*)wglGetProcAddress("gl" #name)))return FALSE
 LOAD(CreateShader);LOAD(ShaderSource);LOAD(CompileShader);LOAD(GetShaderiv);LOAD(GetShaderInfoLog);
 LOAD(CreateProgram);LOAD(AttachShader);LOAD(LinkProgram);LOAD(GetProgramiv);LOAD(UseProgram);LOAD(GetUniformLocation);LOAD(Uniform1i);LOAD(DeleteShader);LOAD(DeleteProgram);LOAD(ActiveTexture);LOAD(TexImage3D);
 #undef LOAD
 size=GetModuleFileNameW(instance,path,MAX_PATH);if(!size || size>=MAX_PATH-5)return FALSE;
 wcscpy(path+size,L".lut");file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);if(file==INVALID_HANDLE_VALUE){log_line("missing color LUT\n");return FALSE;}
 size=GetFileSize(file,NULL);if(size!=12+33*33*33*3){CloseHandle(file);return FALSE;}
 data=HeapAlloc(GetProcessHeap(),0,size);if(!data){CloseHandle(file);return FALSE;}
 ok=ReadFile(file,data,size,&got,NULL)&&got==size&&!memcmp(data,"CYDLUT1",8)&&data[8]==33&&!data[9]&&!data[10]&&!data[11];CloseHandle(file);
 if(!ok){HeapFree(GetProcessHeap(),0,data);return FALSE;}
 pActiveTexture(GL_TEXTURE1);glGenTextures(1,&state.lut);glBindTexture(GL_TEXTURE_3D,state.lut);
 glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
 glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_R,GL_CLAMP_TO_EDGE);
 glPixelStorei(GL_UNPACK_ALIGNMENT,1);glPixelStorei(GL_UNPACK_ROW_LENGTH,0);
 pTexImage3D(GL_TEXTURE_3D,0,GL_RGB,33,33,33,0,GL_RGB,GL_UNSIGNED_BYTE,data+12);HeapFree(GetProcessHeap(),0,data);
 shader=pCreateShader(GL_FRAGMENT_SHADER);pShaderSource(shader,1,&fragment,NULL);pCompileShader(shader);pGetShaderiv(shader,GL_COMPILE_STATUS,&ok);
 if(!ok){char error[512];pGetShaderInfoLog(shader,sizeof(error),NULL,error);log_line(error);pDeleteShader(shader);return FALSE;}
 state.program=pCreateProgram();pAttachShader(state.program,shader);pLinkProgram(state.program);pDeleteShader(shader);pGetProgramiv(state.program,GL_LINK_STATUS,&ok);if(!ok)return FALSE;
 pUseProgram(state.program);pUniform1i(pGetUniformLocation(state.program,"frame"),0);pUniform1i(pGetUniformLocation(state.program,"outputLut"),1);pActiveTexture(GL_TEXTURE0);
 log_line("color_lut=CYDLUT1 edge=33 sRGB-to-capture-profile\n");return glGetError()==GL_NO_ERROR;
}
static BOOL create_gpu(HWND parent,int filter,int width,int height)
{
 WNDCLASSW wc={0};PIXELFORMATDESCRIPTOR pfd={0};int fmt;char dir[MAX_PATH],path[MAX_PATH],line[512];
 HGLRC old=wglGetCurrentContext();HDC olddc=wglGetCurrentDC();DWORD length;
 if(state.child)DestroyWindow(state.child);
 wc.style=CS_OWNDC;wc.lpfnWndProc=window_proc;wc.hInstance=instance;wc.lpszClassName=L"CyderBlueCGFinalBitmapGPU";
 if(!RegisterClassW(&wc) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return FALSE;
 state.parent=parent;state.filter=filter;state.thread=GetCurrentThreadId();
 state.child=CreateWindowExW(WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,wc.lpszClassName,L"",
   WS_CHILD|WS_CLIPSIBLINGS,0,0,width,height,parent,NULL,instance,NULL);
 if(!state.child)return FALSE;
 if((length=GetEnvironmentVariableA("CYDER_GDI_PROFILE_DIR",dir,sizeof(dir)))>0 && length<sizeof(dir)) {
  if(snprintf(path,sizeof(path),"%s\\bluecg-gpu-%08lx.txt",dir,(unsigned long)GetCurrentProcessId())<(int)sizeof(path))
   state.log=CreateFileA(path,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
 }
 state.dc=GetDC(state.child);
 pfd.nSize=sizeof(pfd);pfd.nVersion=1;pfd.dwFlags=PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER;
 pfd.iPixelType=PFD_TYPE_RGBA;pfd.cColorBits=32;pfd.iLayerType=PFD_MAIN_PLANE;
 fmt=ChoosePixelFormat(state.dc,&pfd);
 if(!fmt || !SetPixelFormat(state.dc,fmt,&pfd) || !(state.context=wglCreateContext(state.dc)) || !wglMakeCurrent(state.dc,state.context))goto failed;
 if(!glGetString(GL_RENDERER) || strstr((const char*)glGetString(GL_RENDERER),"Software") || strstr((const char*)glGetString(GL_RENDERER),"llvmpipe"))goto failed;
 {
  BOOL (WINAPI *interval)(int)=(void*)wglGetProcAddress("wglSwapIntervalEXT");
  if(interval)interval(0);
 }
 if(!setup_color_lut())goto failed;
 glGenTextures(1,&state.texture);glBindTexture(GL_TEXTURE_2D,state.texture);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,filter);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,filter);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
 {GLint actual=0;glGetTexParameteriv(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,&actual);if(actual!=filter)goto failed;}
 glDisable(GL_DITHER);glDisable(GL_BLEND);glDisable(GL_DEPTH_TEST);glEnable(GL_TEXTURE_2D);
 glTexEnvi(GL_TEXTURE_ENV,GL_TEXTURE_ENV_MODE,GL_REPLACE);
 glMatrixMode(GL_PROJECTION);glLoadIdentity();glMatrixMode(GL_MODELVIEW);glLoadIdentity();
 snprintf(line,sizeof(line),"renderer=%s\nvendor=%s\nversion=%s\nfilter=%s\nphase=HALFTONE-origin-aligned\nswap_interval=0\n",glGetString(GL_RENDERER),glGetString(GL_VENDOR),glGetString(GL_VERSION),filter==GL_LINEAR?"GL_LINEAR":"GL_NEAREST");log_line(line);
 if(glGetError()!=GL_NO_ERROR)goto failed;
 wglMakeCurrent(olddc,old);state.active=TRUE;return TRUE;
failed:
 state.errors++;wglMakeCurrent(olddc,old);DestroyWindow(state.child);return FALSE;
}
static BOOL source_pixels(HDC source,int sw,int sh,const void **bits,int *pitch,BOOL *topdown)
{
 /* GetObject canonicalizes DIB height in Wine; stage through GDI so orientation is unambiguous. */
 if(!state.staging || state.sw!=sw || state.sh!=sh) {
  BITMAPINFO info;memset(&info,0,sizeof(info));info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=sw;info.bmiHeader.biHeight=-sh;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
  if(state.staging){SelectObject(state.staging,state.previous);DeleteObject(state.bitmap);DeleteDC(state.staging);state.staging=NULL;}
  state.staging=CreateCompatibleDC(source);if(!state.staging)return FALSE;
  state.bitmap=CreateDIBSection(source,&info,DIB_RGB_COLORS,&state.bits,NULL,0);if(!state.bitmap){DeleteDC(state.staging);state.staging=NULL;return FALSE;}
  state.previous=SelectObject(state.staging,state.bitmap);
 }
 if(!BitBlt(state.staging,0,0,sw,sh,source,0,0,SRCCOPY))return FALSE;
 GdiFlush();*bits=state.bits;*pitch=sw*4;*topdown=TRUE;state.copied++;
 if(!state.frames)log_line("upload_path=GDI-copy-top-down-BGRA\n");return TRUE;
}
__declspec(dllexport) BOOL __cdecl bluecg_gpu_present(HWND parent,HDC source,int sw,int sh,int dw,int dh,int linear)
{
 HGLRC old;HDC olddc;const void *pixels;int pitch;BOOL topdown,ok=FALSE;GLfloat dx,dy,top,bottom;
 if(GetWindowThreadProcessId(parent,NULL)!=GetCurrentThreadId())return FALSE;
 if(!state.active || state.parent!=parent || state.filter!=(linear?GL_LINEAR:GL_NEAREST)) {
  if(!create_gpu(parent,linear?GL_LINEAR:GL_NEAREST,dw,dh))return FALSE;
 }
 if(state.thread!=GetCurrentThreadId())return FALSE;
 if(!source_pixels(source,sw,sh,&pixels,&pitch,&topdown))goto failed;
 old=wglGetCurrentContext();olddc=wglGetCurrentDC();
 if(!wglMakeCurrent(state.dc,state.context)){wglMakeCurrent(olddc,old);goto failed;}
 glBindTexture(GL_TEXTURE_2D,state.texture);glPixelStorei(GL_UNPACK_ALIGNMENT,4);glPixelStorei(GL_UNPACK_ROW_LENGTH,pitch/4);
 if(state.sw!=sw || state.sh!=sh){glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,sw,sh,0,GL_BGRA,GL_UNSIGNED_BYTE,pixels);state.sw=sw;state.sh=sh;}
 else glTexSubImage2D(GL_TEXTURE_2D,0,0,0,sw,sh,GL_BGRA,GL_UNSIGNED_BYTE,pixels);
 if(!state.visible || state.dw!=dw || state.dh!=dh) {
  SetWindowPos(state.child,HWND_TOP,0,0,dw,dh,SWP_NOACTIVATE|SWP_NOOWNERZORDER|SWP_SHOWWINDOW);
  state.dw=dw;state.dh=dh;state.visible=TRUE;
 }
 glViewport(0,0,dw,dh);
 /* Match Wine HALFTONE source origin rather than shift the pixel grid by half a texel. */
 dx=0.5f/sw-0.5f/dw;dy=0.5f/sh-0.5f/dh;top=topdown?dy:1-dy;bottom=topdown?1+dy:-dy;
 glBegin(GL_QUADS);
 glTexCoord2f(dx,bottom);glVertex2f(-1,-1);glTexCoord2f(1+dx,bottom);glVertex2f(1,-1);
 glTexCoord2f(1+dx,top);glVertex2f(1,1);glTexCoord2f(dx,top);glVertex2f(-1,1);glEnd();
 ok=glGetError()==GL_NO_ERROR && SwapBuffers(state.dc);
 if(!wglMakeCurrent(olddc,old))ok=FALSE;
 if(ok){state.frames++;return TRUE;}
failed:
 state.errors++;if(state.child)ShowWindow(state.child,SW_HIDE);state.visible=FALSE;log_line("presentation-failed; GDI fallback\n");return FALSE;
}
__declspec(dllexport) void __cdecl bluecg_gpu_hide(HWND parent)
{
 if(state.parent==parent && state.child){ShowWindow(state.child,SW_HIDE);state.visible=FALSE;}
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved)
{
 (void)reserved;if(reason==DLL_PROCESS_ATTACH){instance=module;DisableThreadLibraryCalls(module);}return TRUE;
}
