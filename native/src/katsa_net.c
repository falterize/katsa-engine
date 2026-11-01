/* katsa_net: flat C API over ENet for LuaJIT FFI. Lua never sees ENet structs.
 * Events are returned in a fixed struct; payload memory is valid until the next call to
 * knet_service on the same host. LAN discovery uses plain UDP sockets (broadcast + replies). */
#include <enet/enet.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define KNET_API __declspec(dllexport)
#else
#define KNET_API __attribute__((visibility("default")))
#endif

typedef struct KNetEvent {
    int type;         /* 0 none, 1 connect, 2 disconnect, 3 receive */
    int peer;         /* index in host->peers */
    int channel;
    unsigned int data;
    const unsigned char* payload;
    size_t length;
} KNetEvent;

typedef struct KNetHost {
    ENetHost* host;
    ENetPacket* last;
} KNetHost;

static int initialized = 0;

KNET_API int knet_init(void) {
    if (!initialized && enet_initialize() != 0) {
        return -1;
    }
    initialized = 1;
    return 0;
}

KNET_API void knet_shutdown(void) {
    if (initialized) {
        enet_deinitialize();
        initialized = 0;
    }
}

/* port < 0 creates a client-only host. */
KNET_API KNetHost* knet_host_create(const char* bind, int port, int maxPeers, int channels) {
    ENetAddress address;
    ENetAddress* use = NULL;
    KNetHost* result;
    if (knet_init() != 0) {
        return NULL;
    }
    if (port >= 0) {
        if (bind && bind[0]) {
            if (enet_address_set_host_ip(&address, bind) != 0) {
                return NULL;
            }
        } else {
            address.host = ENET_HOST_ANY;
        }
        address.port = (enet_uint16)port;
        use = &address;
    }
    result = (KNetHost*)calloc(1, sizeof(KNetHost));
    result->host = enet_host_create(use, (size_t)maxPeers, (size_t)channels, 0, 0);
    if (!result->host) {
        free(result);
        return NULL;
    }
    return result;
}

KNET_API void knet_host_destroy(KNetHost* h) {
    if (!h) {
        return;
    }
    if (h->last) {
        enet_packet_destroy(h->last);
    }
    enet_host_destroy(h->host);
    free(h);
}

KNET_API int knet_connect(KNetHost* h, const char* name, int port, int channels) {
    ENetAddress address;
    ENetPeer* peer;
    if (enet_address_set_host(&address, name) != 0) {
        return -1;
    }
    address.port = (enet_uint16)port;
    peer = enet_host_connect(h->host, &address, (size_t)channels, 0);
    return peer ? (int)(peer - h->host->peers) : -1;
}

KNET_API int knet_service(KNetHost* h, int timeoutMs, KNetEvent* out) {
    ENetEvent event;
    int status;
    if (h->last) {
        enet_packet_destroy(h->last);
        h->last = NULL;
    }
    status = enet_host_service(h->host, &event, (enet_uint32)timeoutMs);
    if (status <= 0) {
        out->type = 0;
        return status;
    }
    out->peer = event.peer ? (int)(event.peer - h->host->peers) : -1;
    out->channel = event.channelID;
    out->data = event.data;
    out->payload = NULL;
    out->length = 0;
    switch (event.type) {
    case ENET_EVENT_TYPE_CONNECT:
        out->type = 1;
        break;
    case ENET_EVENT_TYPE_DISCONNECT:
        out->type = 2;
        break;
    case ENET_EVENT_TYPE_RECEIVE:
        out->type = 3;
        out->payload = event.packet->data;
        out->length = event.packet->dataLength;
        h->last = event.packet;
        break;
    default:
        out->type = 0;
    }
    return 1;
}

/* flags: 1 reliable, 2 unsequenced. */
KNET_API int knet_send(KNetHost* h, int peer, int channel, const void* data, size_t length, int flags) {
    enet_uint32 mode = 0;
    ENetPacket* packet;
    if (peer < 0 || (size_t)peer >= h->host->peerCount) {
        return -1;
    }
    if (flags & 1) {
        mode |= ENET_PACKET_FLAG_RELIABLE;
    }
    if (flags & 2) {
        mode |= ENET_PACKET_FLAG_UNSEQUENCED;
    }
    packet = enet_packet_create(data, length, mode);
    if (!packet) {
        return -1;
    }
    if (enet_peer_send(&h->host->peers[peer], (enet_uint8)channel, packet) != 0) {
        enet_packet_destroy(packet);
        return -1;
    }
    return 0;
}

KNET_API void knet_broadcast(KNetHost* h, int channel, const void* data, size_t length, int flags) {
    enet_uint32 mode = 0;
    if (flags & 1) {
        mode |= ENET_PACKET_FLAG_RELIABLE;
    }
    if (flags & 2) {
        mode |= ENET_PACKET_FLAG_UNSEQUENCED;
    }
    enet_host_broadcast(h->host, (enet_uint8)channel, enet_packet_create(data, length, mode));
}

KNET_API void knet_flush(KNetHost* h) {
    enet_host_flush(h->host);
}

KNET_API void knet_disconnect(KNetHost* h, int peer, unsigned int data, int now) {
    if (peer < 0 || (size_t)peer >= h->host->peerCount) {
        return;
    }
    /* mode 1: immediately, 2: after queued packets are sent, 0: normal handshake */
    if (now == 1) {
        enet_peer_disconnect_now(&h->host->peers[peer], data);
    } else if (now == 2) {
        enet_peer_disconnect_later(&h->host->peers[peer], data);
    } else {
        enet_peer_disconnect(&h->host->peers[peer], data);
    }
}

KNET_API void knet_reset(KNetHost* h, int peer) {
    if (peer >= 0 && (size_t)peer < h->host->peerCount) {
        enet_peer_reset(&h->host->peers[peer]);
    }
}

/* Round trip time in ms and loss (0..1) for one peer. */
KNET_API int knet_stats(KNetHost* h, int peer, double* loss) {
    ENetPeer* p;
    if (peer < 0 || (size_t)peer >= h->host->peerCount) {
        return -1;
    }
    p = &h->host->peers[peer];
    if (loss) {
        *loss = (double)p->packetLoss / (double)ENET_PEER_PACKET_LOSS_SCALE;
    }
    return (int)p->roundTripTime;
}

KNET_API int knet_peer_state(KNetHost* h, int peer) {
    if (peer < 0 || (size_t)peer >= h->host->peerCount) {
        return -1;
    }
    return (int)h->host->peers[peer].state;
}

KNET_API int knet_peer_address(KNetHost* h, int peer, char* buffer, size_t size, int* port) {
    if (peer < 0 || (size_t)peer >= h->host->peerCount) {
        return -1;
    }
    *port = h->host->peers[peer].address.port;
    return enet_address_get_host_ip(&h->host->peers[peer].address, buffer, size);
}

KNET_API int knet_connected_count(KNetHost* h) {
    return (int)h->host->connectedPeers;
}

KNET_API void knet_set_timeout(KNetHost* h, int peer, unsigned int limit, unsigned int minimum, unsigned int maximum) {
    if (peer >= 0 && (size_t)peer < h->host->peerCount) {
        enet_peer_timeout(&h->host->peers[peer], limit, minimum, maximum);
    }
}

/* ---- LAN discovery: non-blocking UDP socket with broadcast ---- */

/* Sockets cross the FFI as int (-1 on failure); Windows SOCKET values fit. */
KNET_API int knet_lan_open(int port) {
    ENetSocket socket = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM);
    ENetAddress address;
    if (socket == ENET_SOCKET_NULL) {
        return -1;
    }
    enet_socket_set_option(socket, ENET_SOCKOPT_NONBLOCK, 1);
    enet_socket_set_option(socket, ENET_SOCKOPT_BROADCAST, 1);
    enet_socket_set_option(socket, ENET_SOCKOPT_REUSEADDR, 1);
    if (port >= 0) {
        address.host = ENET_HOST_ANY;
        address.port = (enet_uint16)port;
        if (enet_socket_bind(socket, &address) < 0) {
            enet_socket_destroy(socket);
            return -1;
        }
    }
    return (int)socket;
}

KNET_API void knet_lan_close(int socket) {
    enet_socket_destroy((ENetSocket)socket);
}

/* address NULL or "" sends to the limited broadcast address. */
KNET_API int knet_lan_send(int socket, const char* ip, int port, const void* data, size_t length) {
    ENetAddress address;
    ENetBuffer buffer;
    if (ip && ip[0]) {
        if (enet_address_set_host_ip(&address, ip) != 0) {
            return -1;
        }
    } else {
        address.host = ENET_HOST_BROADCAST;
    }
    address.port = (enet_uint16)port;
    buffer.data = (void*)data;
    buffer.dataLength = length;
    return enet_socket_send((ENetSocket)socket, &address, &buffer, 1);
}

/* Returns bytes received, 0 when nothing is pending, -1 on error. */
KNET_API int knet_lan_receive(int socket, void* data, size_t capacity, char* ip, size_t ipSize, int* port) {
    ENetAddress address;
    ENetBuffer buffer;
    int received;
    buffer.data = data;
    buffer.dataLength = capacity;
    received = enet_socket_receive((ENetSocket)socket, &address, &buffer, 1);
    if (received > 0) {
        enet_address_get_host_ip(&address, ip, ipSize);
        *port = address.port;
    }
    return received;
}
