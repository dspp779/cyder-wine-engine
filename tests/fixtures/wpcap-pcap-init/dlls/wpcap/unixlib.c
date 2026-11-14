/* Minimal stand-in for Wine's dlls/wpcap/unixlib.c around wrap_init(). */
#include <pcap/pcap.h>

typedef int NTSTATUS;
struct init_params { unsigned int opt; char *errbuf; };

static NTSTATUS wrap_init( void *args )
{
    const struct init_params *params = args;
    return pcap_init( params->opt, params->errbuf );
}

static NTSTATUS wrap_lib_version( void *args )
{
    (void)args;
    return 0;
}

NTSTATUS cyder_probe_init( void *args ) { return wrap_init( args ) + wrap_lib_version( args ); }
