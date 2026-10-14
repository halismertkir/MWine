#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

int main(void) {
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_0 };
    D3D_FEATURE_LEVEL level;
    HRESULT result = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
        levels, 1, D3D11_SDK_VERSION, &device, &level, &context);
    if (FAILED(result)) { printf("D3D11CreateDevice failed: 0x%08lx\n", (unsigned long) result); return 1; }
    printf("D3D11 hardware device created; feature level: 0x%x\n", (unsigned)level);
    IDXGIDevice *dxgi = NULL;
    IDXGIAdapter *adapter = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice, (void **)&dxgi))) {
        if (SUCCEEDED(IDXGIDevice_GetAdapter(dxgi, &adapter))) {
            DXGI_ADAPTER_DESC desc;
            if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc))) {
                char name[1024];
                WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof(name), NULL, NULL);
                printf("Adapter: %s\n", name);
            }
            IDXGIAdapter_Release(adapter);
        }
        IDXGIDevice_Release(dxgi);
    }
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    return 0;
}
