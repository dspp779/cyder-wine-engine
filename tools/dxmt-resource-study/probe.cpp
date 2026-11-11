#include <windows.h>
#include <d3d11.h>
#include <wrl/client.h>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
using Microsoft::WRL::ComPtr;
static void ck(HRESULT h,const char*s){if(FAILED(h)){printf("ERROR %s %08lx\n",s,(unsigned long)h);exit(2);}}
static double now(){LARGE_INTEGER n,f;QueryPerformanceCounter(&n);QueryPerformanceFrequency(&f);return 1000.*n.QuadPart/f.QuadPart;}
static D3D11_TEXTURE2D_DESC desc(unsigned w,unsigned h,unsigned a=1){D3D11_TEXTURE2D_DESC d{};d.Width=w;d.Height=h;d.ArraySize=a;d.MipLevels=1;d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;d.SampleDesc.Count=1;d.BindFlags=D3D11_BIND_SHADER_RESOURCE;return d;}
int main(int argc,char**argv){
 setvbuf(stdout,nullptr,_IONBF,0);
 ComPtr<ID3D11Device>d;ComPtr<ID3D11DeviceContext>c;D3D_FEATURE_LEVEL fl;
 ck(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&d,&fl,&c),"device");
 if(argc>1 && !strcmp(argv[1],"overflow")){
   constexpr unsigned slices=2048; unsigned arrays=argc>2?unsigned(atoi(argv[2])):8; if(arrays!=4 && arrays!=8)return 2; unsigned total=slices*arrays;
   std::vector<uint32_t> data(total);std::vector<D3D11_SUBRESOURCE_DATA> init(slices);
   std::vector<ComPtr<ID3D11Texture2D>> tex(arrays);auto td=desc(1,1,slices);
   for(unsigned a=0;a<arrays;a++){
     for(unsigned i=0;i<slices;i++){unsigned n=a*slices+i;data[n]=0xff000000u|(n+1);init[i]={&data[n],4,4};}
     ck(d->CreateTexture2D(&td,init.data(),&tex[a]),"array");
   }
   ComPtr<ID3D11Texture2D> atlas,staging;td=desc(128,128);ck(d->CreateTexture2D(&td,nullptr,&atlas),"atlas");
   td.Usage=D3D11_USAGE_STAGING;td.BindFlags=0;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;ck(d->CreateTexture2D(&td,nullptr,&staging),"staging");
   for(unsigned n=0;n<total;n++)c->CopySubresourceRegion(atlas.Get(),0,n%128,n/128,0,tex[n/slices].Get(),n%slices,nullptr);
   c->CopyResource(staging.Get(),atlas.Get());D3D11_MAPPED_SUBRESOURCE m{};ck(c->Map(staging.Get(),0,D3D11_MAP_READ,0,&m),"map");
   unsigned bad=0;for(unsigned n=0;n<total;n++){uint32_t actual;memcpy(&actual,(char*)m.pData+(n/128)*m.RowPitch+(n%128)*4,4);if(actual!=data[n]){if(bad<16)printf("MISMATCH slice=%u expected=%08x got=%08x\n",n,data[n],actual);bad++;}}
   c->Unmap(staging.Get(),0);printf("OVERFLOW checked=%u mismatches=%u\n",total,bad);c->ClearState();c->Flush();return bad?1:0;
 }
 constexpr unsigned w=257,h=512,count=64;
 auto td=desc(w,h);ComPtr<ID3D11Texture2D> staging;auto sd=td;sd.Usage=D3D11_USAGE_STAGING;sd.BindFlags=0;sd.CPUAccessFlags=D3D11_CPU_ACCESS_READ;ck(d->CreateTexture2D(&sd,nullptr,&staging),"staging");
 unsigned modes[]={0,1,1,0,0,1,1,0,0,1};
 for(unsigned trial=0;trial<10;trial++){
   unsigned pitch=modes[trial]?1280:w*4;std::vector<unsigned char> bytes(pitch*h,0xad);
   for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){uint32_t v=0xff000000u|(y*w+x);memcpy(bytes.data()+y*pitch+x*4,&v,4);}
   D3D11_SUBRESOURCE_DATA init{bytes.data(),pitch,pitch*h};std::vector<ComPtr<ID3D11Texture2D>> tex(count);
   double t0=now();for(auto&t:tex)ck(d->CreateTexture2D(&td,&init,&t),"texture");double t1=now();
   // Sample all textures; one staging Map drains each copy and validates pixels.
   unsigned bad=0;double copy0=now();
   for(auto&t:tex){c->CopyResource(staging.Get(),t.Get());D3D11_MAPPED_SUBRESOURCE m{};ck(c->Map(staging.Get(),0,D3D11_MAP_READ,0,&m),"map");for(unsigned y=0;y<h;y++)if(memcmp((char*)m.pData+y*m.RowPitch,bytes.data()+y*pitch,w*4))bad++;c->Unmap(staging.Get(),0);}
   double t2=now();printf("UPLOAD trial=%u padded=%u textures=%u create_ms=%.3f copy_map_verify_ms=%.3f bad_rows=%u\n",trial,modes[trial],count,t1-t0,t2-copy0,bad);if(bad)return 1;
 }
 c->ClearState();c->Flush();return 0;
}
