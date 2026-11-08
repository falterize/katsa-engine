/*
 * katsa_net / host: ENet hosts, events and peers.
 *
 * A host is a server when created with a port, or a client-only host (port < 0) that connects
 * out. Lua calls knet_service every frame until it reports no event (source/katsa/net/host.lua).
 */
#include <stdlib.h>
#include <string.h>

#include "net.h"

static int initialized = 0;

/* ---------------------------------------------------------------------------------------------- */
/* Helpers                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

static int valid_peer(const KNetHost* h, int peer) {
    return peer >= 0 && (size_t)peer < h->host->peerCount;
}

static enet_uint32 packet_flags(int flags) {
    enet_uint32 mode = 0;
    if (flags & KNET_SEND_RELIABLE) {
        mode |= ENET_PACKET_FLAG_RELIABLE;
    }
    if (flags & KNET_SEND_UNSEQUENCED) {
        mode |= ENET_PACKET_FLAG_UNSEQUENCED;
    }
    return mode;
}

static void release_last_packet(KNetHost* h) {
    if (h->last) {
        enet_packet_destroy(h->last);
        h->last = NULL;
    }
}

/* ---------------------------------------------------------------------------------------------- */
/* Library lifetime                                                                               */
/* ---------------------------------------------------------------------------------------------- */

/* Returns 0 on success (also when already initialized), -1 when ENet cannot start. */
KATSA_EXPORT int knet_init(void) {
    if (!initialized && enet_initialize() != 0) {
        return -1;
    }
    initialized = 1;
    return 0;
}

KATSA_EXPORT void knet_shutdown(void) {
    if (initialized) {
        enet_deinitialize();
        initialized = 0;
    }
}

/* 1: this library keeps ENet's unreliable-packet throttle off (see knet_service). Libraries built
 * before that fix lack the function, which tells Lua to send its state reliably instead. */
KATSA_EXPORT int knet_unthrottled(void) {
    return 1;
}

/* ---------------------------------------------------------------------------------------------- */
/* Hosts                                                                                          */
/* ---------------------------------------------------------------------------------------------- */

/*
 * Creates a host. With port >= 0 it listens on that port (on `bind`, an IP address, or on every
 * interface when `bind` is NULL or ""); with port < 0 it is a client-only host. `maxPeers` limits
 * connections, `channels` the channels per connection. Returns NULL on failure.
 */
KATSA_EXPORT KNetHost* knet_host_create(const char* bind, int port, int maxPeers, int channels) {
    if (knet_init() != 0) {
        return NULL;
    }
    ENetAddress address;
    ENetAddress* listen = NULL;
    if (port >= 0) {
        if (bind && bind[0]) {
            if (enet_address_set_host_ip(&address, bind) != 0) {
                return NULL;
            }
        } else {
            address.host = ENET_HOST_ANY;
        }
        address.port = (enet_uint16)port;
        listen = &address;
    }
    KNetHost* h = (KNetHost*)calloc(1, sizeof(KNetHost));
    if (!h) {
        return NULL;
    }
    /* 0, 0: no bandwidth limits; ENet adapts to the link. */
    h->host = enet_host_create(listen, (size_t)maxPeers, (size_t)channels, 0, 0);
    if (!h->host) {
        free(h);
        return NULL;
    }
    return h;
}

/* Drops every connection without notice and frees the host. */
KATSA_EXPORT void knet_host_destroy(KNetHost* h) {
    if (!h) {
        return;
    }
    release_last_packet(h);
    enet_host_destroy(h->host);
    free(h);
}

/*
 * Starts connecting to `name` (an IP address or a host name, resolved here and blocking for the
 * DNS lookup) on `port`. Returns the peer index, or -1. The connection is established once
 * knet_service reports KNET_EVENT_CONNECT for that peer.
 */
KATSA_EXPORT int knet_connect(KNetHost* h, const char* name, int port, int channels) {
    ENetAddress address;
    if (enet_address_set_host(&address, name) != 0) {
        return -1;
    }
    address.port = (enet_uint16)port;
    ENetPeer* peer = enet_host_connect(h->host, &address, (size_t)channels, 0);
    return peer ? (int)(peer - h->host->peers) : -1;
}

/*
 * Sends queued packets and waits up to `timeoutMs` for one event, which it writes to `out`.
 * Returns 1 when an event was written, 0 when there was none (out->type = KNET_EVENT_NONE), and a
 * negative value on failure.
 *
 * The payload of a receive event stays valid until the next call on the same host.
 */
KATSA_EXPORT int knet_service(KNetHost* h, int timeoutMs, KNetEvent* out) {
    release_last_packet(h);
    ENetEvent event;
    int status = enet_host_service(h->host, &event, (enet_uint32)timeoutMs);
    if (status <= 0) {
        out->type = KNET_EVENT_NONE;
        return status;
    }
    out->peer = event.peer ? (int)(event.peer - h->host->peers) : -1;
    out->channel = event.channelID;
    out->data = event.data;
    out->payload = NULL;
    out->length = 0;
    switch (event.type) {
    case ENET_EVENT_TYPE_CONNECT:
        out->type = KNET_EVENT_CONNECT;
        /* ENet silently drops unreliable packets while its throttle is low, and a frame-paced
         * loopback (one RTT sample per frame, with hitches) pushes the throttle down: the server
         * sent 20 snapshots/s and the client got 2-7 for the first seconds, with 0% reported
         * loss. A zero deceleration keeps the throttle at its maximum. Do not remove: the cause
         * took several rounds of testing on real hardware to find (docs/changelog.md, v108.5). */
        enet_peer_throttle_configure(event.peer, 5000, 2, 0);
        break;
    case ENET_EVENT_TYPE_DISCONNECT:
        out->type = KNET_EVENT_DISCONNECT;
        break;
    case ENET_EVENT_TYPE_RECEIVE:
        out->type = KNET_EVENT_RECEIVE;
        out->payload = event.packet->data;
        out->length = event.packet->dataLength;
        h->last = event.packet; /* freed by the next call, see KNetHost */
        break;
    default:
        out->type = KNET_EVENT_NONE;
    }
    return 1;
}

/* Sends everything queued now instead of at the next knet_service. */
KATSA_EXPORT void knet_flush(KNetHost* h) {
    enet_host_flush(h->host);
}

/* Number of peers in the connected state. */
KATSA_EXPORT int knet_connected_count(KNetHost* h) {
    return (int)h->host->connectedPeers;
}

/* ---------------------------------------------------------------------------------------------- */
/* Sending                                                                                        */
/* ---------------------------------------------------------------------------------------------- */

/* Queues `data` (copied) for one peer. `flags` is a KNET_SEND_* set. Returns 0, or -1. */
KATSA_EXPORT int knet_send(KNetHost* h, int peer, int channel, const void* data, size_t length,
                           int flags) {
    if (!valid_peer(h, peer)) {
        return -1;
    }
    ENetPacket* packet = enet_packet_create(data, length, packet_flags(flags));
    if (!packet) {
        return -1;
    }
    if (enet_peer_send(&h->host->peers[peer], (enet_uint8)channel, packet) != 0) {
        enet_packet_destroy(packet); /* ENet only takes ownership on success */
        return -1;
    }
    return 0;
}

/* Queues `data` (copied) for every connected peer. */
KATSA_EXPORT void knet_broadcast(KNetHost* h, int channel, const void* data, size_t length,
                                 int flags) {
    ENetPacket* packet = enet_packet_create(data, length, packet_flags(flags));
    if (packet) {
        enet_host_broadcast(h->host, (enet_uint8)channel, packet);
    }
}

/* ---------------------------------------------------------------------------------------------- */
/* Peers                                                                                          */
/* ---------------------------------------------------------------------------------------------- */

/* Disconnects one peer. `now` is a KNET_DISCONNECT_* mode; `data` reaches the other side's
 * disconnect event (Lua uses it as the kick reason code). */
KATSA_EXPORT void knet_disconnect(KNetHost* h, int peer, unsigned int data, int now) {
    if (!valid_peer(h, peer)) {
        return;
    }
    ENetPeer* p = &h->host->peers[peer];
    if (now == KNET_DISCONNECT_NOW) {
        enet_peer_disconnect_now(p, data);
    } else if (now == KNET_DISCONNECT_LATER) {
        enet_peer_disconnect_later(p, data);
    } else {
        enet_peer_disconnect(p, data);
    }
}

/* Forgets a peer at once without telling it. */
KATSA_EXPORT void knet_reset(KNetHost* h, int peer) {
    if (valid_peer(h, peer)) {
        enet_peer_reset(&h->host->peers[peer]);
    }
}

/* Returns the round-trip time in milliseconds (or -1 for a bad index) and writes the packet loss
 * as a fraction 0..1 to `loss` when it is not NULL. */
KATSA_EXPORT int knet_stats(KNetHost* h, int peer, double* loss) {
    if (!valid_peer(h, peer)) {
        return -1;
    }
    ENetPeer* p = &h->host->peers[peer];
    if (loss) {
        *loss = (double)p->packetLoss / (double)ENET_PEER_PACKET_LOSS_SCALE;
    }
    return (int)p->roundTripTime;
}

/* ENet's ENetPeerState value (Lua maps it to names in peer.lua), or -1 for a bad index. */
KATSA_EXPORT int knet_peer_state(KNetHost* h, int peer) {
    if (!valid_peer(h, peer)) {
        return -1;
    }
    return (int)h->host->peers[peer].state;
}

/* Writes the peer's IP address as text into `buffer` and its port to `port`. Returns 0, or -1. */
KATSA_EXPORT int knet_peer_address(KNetHost* h, int peer, char* buffer, size_t size, int* port) {
    if (!valid_peer(h, peer)) {
        return -1;
    }
    *port = h->host->peers[peer].address.port;
    return enet_address_get_host_ip(&h->host->peers[peer].address, buffer, size);
}

/*
 * ENet's disconnect timeout for one peer, in milliseconds: the peer is dropped when it has not
 * answered for `minimum` ms and `limit` retries, or always after `maximum` ms. 0 keeps ENet's
 * default for that value.
 */
KATSA_EXPORT void knet_set_timeout(KNetHost* h, int peer, unsigned int limit, unsigned int minimum,
                                   unsigned int maximum) {
    if (valid_peer(h, peer)) {
        enet_peer_timeout(&h->host->peers[peer], limit, minimum, maximum);
    }
}
