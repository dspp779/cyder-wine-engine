#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: gst-probe /absolute/libgstreamer.dylib\n");
        return 2;
    }
    void *handle = dlopen(argv[1], RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "%s\n", dlerror());
        return 1;
    }
    void (*init)(int *, char ***) = dlsym(handle, "gst_init");
    void *(*find)(const char *) = dlsym(handle, "gst_element_factory_find");
    void (*unref)(void *) = dlsym(handle, "gst_object_unref");
    if (!init || !find || !unref) {
        fprintf(stderr, "required GStreamer symbols unavailable\n");
        return 2;
    }
    init(NULL, NULL);
    const char *names[] = {"videoconvert", "h264parse", "vtdec", "vtdec_hw",
                           "avdec_h264", "decodebin", "qtdemux"};
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        void *factory = find(names[i]);
        printf("%s=%s\n", names[i], factory ? "found" : "missing");
        if (factory) unref(factory);
    }
    return 0;
}
