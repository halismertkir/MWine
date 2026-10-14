/* Small native diagnostic. This verifies the bundled MoltenVK driver, not game compatibility. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <dlfcn.h>

typedef struct {
    uint32_t type; const void *next; const char *name; uint32_t version;
    const char *engine; uint32_t engineVersion; uint32_t apiVersion;
} AppInfo;
typedef struct {
    uint32_t type; const void *next; uint32_t flags; const AppInfo *app;
    uint32_t layerCount; const char *const *layers;
    uint32_t extensionCount; const char *const *extensions;
} InstanceInfo;
typedef struct {
    uint32_t apiVersion, driverVersion, vendor, device, type;
    char name[256]; uint8_t cacheID[16]; uint64_t remainingProperties[512];
} DeviceProperties;

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "Usage: vulkan-probe /path/libMoltenVK.dylib\n"); return 2; }
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int32_t (*version)(uint32_t *) = dlsym(library, "vkEnumerateInstanceVersion");
    int32_t (*create)(const InstanceInfo *, const void *, void **) = dlsym(library, "vkCreateInstance");
    int32_t (*enumerate)(void *, uint32_t *, void **) = dlsym(library, "vkEnumeratePhysicalDevices");
    void (*properties)(void *, DeviceProperties *) = dlsym(library, "vkGetPhysicalDeviceProperties");
    void (*destroy)(void *, const void *) = dlsym(library, "vkDestroyInstance");
    if (!version || !create || !enumerate || !properties || !destroy) return 1;
    uint32_t api = 0;
    if (version(&api)) return 1;
    printf("MoltenVK instance API: %u.%u.%u\n", api >> 22, (api >> 12) & 1023, api & 4095);
    AppInfo app = {0, NULL, "M Wine diagnostic", 1, "M Wine", 1, (1u << 22) | (3u << 12)};
    /* Direct ICD loading bypasses the Vulkan loader's portability enumeration extension. */
    InstanceInfo info = {1, NULL, 0, &app, 0, NULL, 0, NULL};
    void *instance = NULL;
    int32_t result = create(&info, NULL, &instance);
    if (result) { fprintf(stderr, "vkCreateInstance failed: %d\n", result); return 1; }
    uint32_t count = 0;
    result = enumerate(instance, &count, NULL);
    if (result || count == 0) { destroy(instance, NULL); return 1; }
    void **devices = calloc(count, sizeof(void *));
    if (!devices) { destroy(instance, NULL); return 1; }
    result = enumerate(instance, &count, devices);
    if (result) { free(devices); destroy(instance, NULL); return 1; }
    for (uint32_t i = 0; i < count; ++i) {
        DeviceProperties props = {0};
        properties(devices[i], &props);
        printf("GPU: %s; device Vulkan API: %u.%u.%u\n", props.name, props.apiVersion >> 22,
               (props.apiVersion >> 12) & 1023, props.apiVersion & 4095);
    }
    free(devices);
    destroy(instance, NULL);
    dlclose(library);
    return 0;
}
