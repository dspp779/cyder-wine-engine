#include <initializer_list>
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
using Microsoft::WRL::ComPtr;
static void check(HRESULT hr, const char *step) {
  if (FAILED(hr)) { std::fprintf(stderr, "FAIL %s hr=%08lx\n", step, (unsigned long)hr); std::exit(1); }
}
static ComPtr<ID3DBlob> compile(const char *text, const char *target) {
  ComPtr<ID3DBlob> code, error;
  HRESULT hr=D3DCompile(text, std::strlen(text), nullptr, nullptr, nullptr, "main", target, 0, 0, &code, &error);
  if (FAILED(hr) && error) std::fprintf(stderr, "%s\n", (char*)error->GetBufferPointer());
  check(hr,"compile"); return code;
}
int main() {
  ComPtr<ID3D11Device> device; ComPtr<ID3D11DeviceContext> ctx;
  D3D_FEATURE_LEVEL level;
  check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,0,nullptr,0,D3D11_SDK_VERSION,&device,&level,&ctx),"device");
  auto vs=compile("float4 main(uint id:SV_VertexID):SV_Position { float2 p=id==0?float2(-1,-1):(id==1?float2(-1,3):float2(3,-1)); return float4(p,0,1); }","vs_5_0");
  ComPtr<ID3D11VertexShader> vertex;
  check(device->CreateVertexShader(vs->GetBufferPointer(),vs->GetBufferSize(),nullptr,&vertex),"vertex");
  D3D11_TEXTURE2D_DESC td{};td.Width=32;td.Height=32;td.MipLevels=1;td.ArraySize=1;td.Format=DXGI_FORMAT_R8G8B8A8_UNORM;td.SampleDesc.Count=1;td.BindFlags=D3D11_BIND_RENDER_TARGET;
  ComPtr<ID3D11Texture2D> target,staging;
  check(device->CreateTexture2D(&td,nullptr,&target),"target");
  td.BindFlags=0;td.Usage=D3D11_USAGE_STAGING;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
  check(device->CreateTexture2D(&td,nullptr,&staging),"staging");
  ComPtr<ID3D11RenderTargetView> rtv;check(device->CreateRenderTargetView(target.Get(),nullptr,&rtv),"rtv");
  D3D11_RASTERIZER_DESC rd{};rd.FillMode=D3D11_FILL_SOLID;rd.CullMode=D3D11_CULL_NONE;rd.DepthClipEnable=TRUE;
  ComPtr<ID3D11RasterizerState> raster;check(device->CreateRasterizerState(&rd,&raster),"raster");
  D3D11_VIEWPORT viewport{0,0,32,32,0,1};ctx->RSSetViewports(1,&viewport);ctx->RSSetState(raster.Get());
  auto view=rtv.Get();ctx->OMSetRenderTargets(1,&view,nullptr);ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);ctx->VSSetShader(vertex.Get(),nullptr,0);
  const char *pixel[]={"float4 main():SV_Target { return float4(1,0,0,1); }","float4 main():SV_Target { return float4(0,1,0,1); }"};
  for (unsigned color=0;color<2;color++) {
    auto ps=compile(pixel[color],"ps_5_0");ComPtr<ID3D11PixelShader> shader;
    check(device->CreatePixelShader(ps->GetBufferPointer(),ps->GetBufferSize(),nullptr,&shader),"pixel");ctx->PSSetShader(shader.Get(),nullptr,0);
    for (unsigned mask: {0xffffffffu,0u}) {
      float clear[]={0,0,0,1};ctx->ClearRenderTargetView(rtv.Get(),clear);ctx->OMSetBlendState(nullptr,nullptr,mask);
      LARGE_INTEGER start,end,freq;QueryPerformanceFrequency(&freq);QueryPerformanceCounter(&start);
      ctx->Draw(3,0);ctx->CopyResource(staging.Get(),target.Get());
      D3D11_MAPPED_SUBRESOURCE mapped{};check(ctx->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"readback");
      unsigned char expected[]={0,0,0,255};if(mask)expected[color]=255;
      for(unsigned y=0;y<32;y++)for(unsigned x=0;x<32;x++) {
        auto p=(unsigned char*)mapped.pData+y*mapped.RowPitch+x*4;
        if(std::memcmp(p,expected,4)) { std::fprintf(stderr,"FAIL pixel color=%u mask=%x xy=%u,%u rgba=%u,%u,%u,%u\n",color,mask,x,y,p[0],p[1],p[2],p[3]);return 2; }
      }
      ctx->Unmap(staging.Get(),0);QueryPerformanceCounter(&end);
      std::printf("PASS color=%u mask=%08x pixels=1024 draw_readback_ms=%.3f\n",color,mask,1000.*(end.QuadPart-start.QuadPart)/freq.QuadPart);
    }
  }
  ctx->ClearState();ctx->Flush();std::puts("PASS all 4096 pixels");return 0;
}
