-- FFI declarations for katsa_net (flat API over ENet; see native/src/katsa_net.c).
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
typedef struct KNetHost KNetHost;
typedef struct KNetEvent {
    int type;
    int peer;
    int channel;
    unsigned int data;
    const unsigned char* payload;
    size_t length;
} KNetEvent;
int knet_init(void);
void knet_shutdown(void);
KNetHost* knet_host_create(const char* bind, int port, int maxPeers, int channels);
void knet_host_destroy(KNetHost* host);
int knet_connect(KNetHost* host, const char* name, int port, int channels);
int knet_service(KNetHost* host, int timeoutMs, KNetEvent* out);
int knet_send(KNetHost* host, int peer, int channel, const void* data, size_t length, int flags);
void knet_broadcast(KNetHost* host, int channel, const void* data, size_t length, int flags);
void knet_flush(KNetHost* host);
void knet_disconnect(KNetHost* host, int peer, unsigned int data, int now);
void knet_reset(KNetHost* host, int peer);
int knet_stats(KNetHost* host, int peer, double* loss);
int knet_peer_state(KNetHost* host, int peer);
int knet_peer_address(KNetHost* host, int peer, char* buffer, size_t size, int* port);
int knet_connected_count(KNetHost* host);
int knet_unthrottled(void);
void knet_set_timeout(KNetHost* host, int peer, unsigned int limit, unsigned int minimum, unsigned int maximum);
int knet_lan_open(int port);
void knet_lan_close(int socket);
int knet_lan_send(int socket, const char* ip, int port, const void* data, size_t length);
int knet_lan_receive(int socket, void* data, size_t capacity, char* ip, size_t ipSize, int* port);
]])

local library
local Binding = {}

function Binding.lib()
    if not library then
        library = assert(Native.load('Net'))
        assert(library.knet_init() == 0, 'Network library could not be initialized')
    end
    return library
end

-- Whether the loaded native library keeps ENet's unreliable-packet throttle off. An older library
-- (built before the fix) loses most unreliable packets for the first seconds of a connection, so
-- the engine sends its state packets reliably until the library is rebuilt.
function Binding.unthrottled()
    if Binding.throttleChecked == nil then
        local ok, result = pcall(function()
            return Binding.lib().knet_unthrottled() == 1
        end)
        Binding.throttleChecked = ok and result or false
    end
    return Binding.throttleChecked
end

return Binding
