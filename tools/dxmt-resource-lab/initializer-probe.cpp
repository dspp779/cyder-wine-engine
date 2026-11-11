#include <windows.h>
#include <d3d11.h>
#include <wrl/client.h>
#include <vector>
#include <string>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
using Microsoft::WRL::ComPtr;
static void ck(HRESULT hr,const char *what){if(FAILED(hr)){printf("FAIL %s hr=%08lx\n",what,(unsigned long)hr);exit(2);}}
static D3D11_TEXTURE2D_DESC desc(unsigned w,unsigned h){D3D11_TEXTURE2D_DESC d{};d.Width=w;d.Height=h;d.ArraySize=1;d.MipLevels=1;d.Format=DXGI_FORMAT_R8G8B8A8_UNORM;d.SampleDesc.Count=1;d.BindFlags=D3D11_BIND_SHADER_RESOURCE;return d;}
static unsigned verify(ID3D11Device*d,ID3D11DeviceContext*c,ID3D11Texture2D*t,bool zero,uint32_t value){
 D3D11_TEXTURE2D_DESC td;t->GetDesc(&td);td.Usage=D3D11_USAGE_STAGING;td.BindFlags=0;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;td.MiscFlags=0;
 ComPtr<ID3D11Texture2D> st;ck(d->CreateTexture2D(&td,nullptr,&st),"staging");c->CopyResource(st.Get(),t);
 D3D11_MAPPED_SUBRESOURCE m{};ck(c->Map(st.Get(),0,D3D11_MAP_READ,0,&m),"map");
 unsigned bad=0;for(unsigned y=0;y<td.Height;y++)for(unsigned x=0;x<td.Width;x++){uint32_t v;memcpy(&v,(char*)m.pData+y*m.RowPitch+x*4,4);if(v!=(zero?0:value))bad++;}c->Unmap(st.Get(),0);return bad;
}
int main(int argc,char**argv){
 setvbuf(stdout,nullptr,_IONBF,0);std::string mode=argc>1?argv[1]:"mixed";
 ComPtr<ID3D11Device>d;ComPtr<ID3D11DeviceContext>c;D3D_FEATURE_LEVEL fl;
 ck(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&d,&fl,&c),"device");
 unsigned bad=0,failures=0,successes=0,pixels=0;
 std::vector<ComPtr<ID3D11Texture2D>> textures;std::vector<bool> zero;std::vector<uint32_t> values;
 if(mode=="mixed"){
  // Different sizes grow the zero buffer repeatedly before any explicit Flush.
  // Mix uploads and RT/DS clears to exercise both initializer command lists.
  for(unsigned i=1;i<=96;i++){
   auto td=desc(i,i+1);unsigned kind=i%4;bool z=kind!=0;
   if(kind==1)td.BindFlags=D3D11_BIND_RENDER_TARGET;
   if(kind==2){td.Format=DXGI_FORMAT_D32_FLOAT;td.BindFlags=D3D11_BIND_DEPTH_STENCIL;}
   uint32_t value=0xff000000u+i;std::vector<uint32_t> data(td.Width*td.Height,value);D3D11_SUBRESOURCE_DATA init{data.data(),td.Width*4,td.Width*td.Height*4};
   ComPtr<ID3D11Texture2D> t;ck(d->CreateTexture2D(&td,z?nullptr:&init,&t),"mixed create");
   // Overwrite CPU source immediately: initialization must have consumed it.
   std::fill(data.begin(),data.end(),0xdeadbeef);textures.push_back(t);zero.push_back(z);values.push_back(value);pixels+=td.Width*td.Height;
  }
 }else if(mode=="fault"||mode=="fault-clear"||mode=="fault-depth"){
  char site[64]{};GetEnvironmentVariableA("DXMT_CYDER_TEST_FAIL",site,sizeof(site));
  bool z=!strcmp(site,"zero")||mode!="fault";
  for(unsigned i=1;i<=8;i++){
   auto td=desc(i,i+1);if(mode=="fault-clear")td.BindFlags=D3D11_BIND_RENDER_TARGET;
   if(mode=="fault-depth"){td.BindFlags=D3D11_BIND_DEPTH_STENCIL;td.Format=DXGI_FORMAT_D32_FLOAT;}
   uint32_t value=0xff000000u+i;std::vector<uint32_t> data(td.Width*td.Height,value);D3D11_SUBRESOURCE_DATA init{data.data(),td.Width*4,td.Width*td.Height*4};
   ID3D11Texture2D *raw=reinterpret_cast<ID3D11Texture2D*>(uintptr_t(1));
   HRESULT hr=d->CreateTexture2D(&td,z?nullptr:&init,&raw);
   if(hr==E_OUTOFMEMORY){if(raw!=nullptr){puts("FAIL nonnull output on OOM");return 2;}failures++;continue;}
   ck(hr,"fault create");ComPtr<ID3D11Texture2D> t;t.Attach(raw);textures.push_back(t);zero.push_back(z);values.push_back(value);successes++;
  }
  bool always=GetEnvironmentVariableA("DXMT_CYDER_TEST_FAIL_ALWAYS",nullptr,0)>0;
  if((!always&&failures!=1)||(always&&failures<7)){printf("FAIL unexpected fault count=%u\n",failures);return 2;}
 }else if(mode=="fault-buffer"){
  std::vector<ComPtr<ID3D11Buffer>> buffers;
  for(unsigned i=0;i<8;i++){D3D11_BUFFER_DESC bd{};bd.ByteWidth=256;bd.BindFlags=D3D11_BIND_UNORDERED_ACCESS;ComPtr<ID3D11Buffer>b;
   HRESULT hr=d->CreateBuffer(&bd,nullptr,&b);if(hr==E_OUTOFMEMORY){if(b)return 2;failures++;continue;}ck(hr,"buffer");buffers.push_back(b);}
  if(failures!=1)return 2;
  for(auto&b:buffers){D3D11_BUFFER_DESC bd{};b->GetDesc(&bd);bd.BindFlags=0;bd.Usage=D3D11_USAGE_STAGING;bd.CPUAccessFlags=D3D11_CPU_ACCESS_READ;ComPtr<ID3D11Buffer>s;ck(d->CreateBuffer(&bd,nullptr,&s),"buffer staging");c->CopyResource(s.Get(),b.Get());D3D11_MAPPED_SUBRESOURCE m{};ck(c->Map(s.Get(),0,D3D11_MAP_READ,0,&m),"buffer map");for(unsigned i=0;i<bd.ByteWidth;i++)if(((unsigned char*)m.pData)[i])bad++;c->Unmap(s.Get(),0);}
 }else{return 2;}
 for(unsigned i=0;i<textures.size();i++)bad+=verify(d.Get(),c.Get(),textures[i].Get(),zero[i],values[i]);
 c->ClearState();c->Flush();printf("INIT_RESULT mode=%s textures=%zu pixels=%u failures=%u bad=%u\n",mode.c_str(),textures.size(),pixels,failures,bad);return bad?1:0;
}
