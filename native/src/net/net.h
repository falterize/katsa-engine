/*
 * katsa_net: a flat C interface to ENet for katsa.net (LuaJIT FFI). Lua never sees ENet structs.
 *
 * Files:
 *   host.c   hosts (server or client), events, sending, per-peer state
 *   lan.c    LAN discovery over plain non-blocking UDP sockets (broadcast and replies)
 *
 * Conventions:
 *   - Peers are identified by their index in the host's peer array (0-based); functions taking a
 *     peer index ignore or reject indices outside it.
 *   - Channels are 0-based here; the Lua API is 1-based and subtracts one.
 *   - The codes below are part of the ABI: the Lua files in source/katsa/net use the same numbers.
 *
 * Lua declarations: source/katsa/net/binding.lua.
 */
#ifndef KATSA_NET_H
#define KATSA_NET_H

#include <stddef.h>

#include <enet/enet.h>

#include "common/export.h"

/* KNetEvent.type. Lua: source/katsa/net/host.lua. */
enum {
    KNET_EVENT_NONE = 0,
    KNET_EVENT_CONNECT = 1,
    KNET_EVENT_DISCONNECT = 2,
    KNET_EVENT_RECEIVE = 3,
};

/* `flags` of knet_send / knet_broadcast (a bit set). Lua: source/katsa/net/peer.lua, host.lua. */
enum {
    KNET_SEND_RELIABLE = 1,
    KNET_SEND_UNSEQUENCED = 2,
};

/* `now` of knet_disconnect. Lua: source/katsa/net/peer.lua. */
enum {
    KNET_DISCONNECT_GRACEFUL = 0, /* handshake: the peer is told and acknowledges */
    KNET_DISCONNECT_NOW = 1,      /* drop at once; the peer only gets a best-effort notice */
    KNET_DISCONNECT_LATER = 2,    /* graceful, after the queued outgoing packets are sent */
};

/* One network event, filled by knet_service. Layout is mirrored by ffi.cdef in binding.lua. */
typedef struct KNetEvent {
    int type;                     /* KNET_EVENT_* */
    int peer;                     /* peer index, -1 when the event has no peer */
    int channel;                  /* receive: the channel the packet arrived on */
    unsigned int data;            /* connect/disconnect: the 32-bit value the other side sent */
    const unsigned char* payload; /* receive: packet bytes, valid until the next knet_service */
    size_t length;                /* receive: payload size in bytes */
} KNetEvent;

/* A host handle. `last` is the packet of the latest receive event: it is kept alive so Lua can
 * read KNetEvent.payload without a copy, and freed by the next knet_service call. */
typedef struct KNetHost {
    ENetHost* host;
    ENetPacket* last;
} KNetHost;

/* Initializes ENet once per process; every other entry point calls it as needed. */
KATSA_EXPORT int knet_init(void);

#endif
