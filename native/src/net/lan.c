/*
 * katsa_net / lan: LAN discovery over plain UDP.
 *
 * A server answers on a known port; clients broadcast a query and read the replies. These are
 * ordinary non-blocking datagram sockets with broadcast enabled (no ENet connection). The
 * message format is Lua's business (source/katsa/net/lan.lua).
 *
 * Sockets cross the FFI as int (-1 on failure). On 64-bit Windows a SOCKET is pointer sized, but
 * the values Windows hands out are small handles that fit in an int.
 */
#include <stddef.h>

#include "net.h"

/* Opens a UDP socket, bound to `port` on every interface when port >= 0 (a server), unbound
 * otherwise (a client; the system picks a port on the first send). */
KATSA_EXPORT int knet_lan_open(int port) {
    if (knet_init() != 0) {
        return -1;
    }
    ENetSocket socket = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM);
    if (socket == ENET_SOCKET_NULL) {
        return -1;
    }
    enet_socket_set_option(socket, ENET_SOCKOPT_NONBLOCK, 1);
    enet_socket_set_option(socket, ENET_SOCKOPT_BROADCAST, 1);
    /* Several games on one machine may listen for discovery on the same port. */
    enet_socket_set_option(socket, ENET_SOCKOPT_REUSEADDR, 1);
    if (port >= 0) {
        ENetAddress address;
        address.host = ENET_HOST_ANY;
        address.port = (enet_uint16)port;
        if (enet_socket_bind(socket, &address) < 0) {
            enet_socket_destroy(socket);
            return -1;
        }
    }
    return (int)socket;
}

KATSA_EXPORT void knet_lan_close(int socket) {
    enet_socket_destroy((ENetSocket)socket);
}

/* Sends one datagram to `ip`:`port`, or to the limited broadcast address 255.255.255.255 when
 * `ip` is NULL or "". Returns the bytes sent, 0 when the socket would block, or -1. */
KATSA_EXPORT int knet_lan_send(int socket, const char* ip, int port, const void* data,
                               size_t length) {
    ENetAddress address;
    if (ip && ip[0]) {
        if (enet_address_set_host_ip(&address, ip) != 0) {
            return -1;
        }
    } else {
        address.host = ENET_HOST_BROADCAST;
    }
    address.port = (enet_uint16)port;
    ENetBuffer buffer;
    buffer.data = (void*)data; /* ENet's buffer type is not const; the data is only read */
    buffer.dataLength = length;
    return enet_socket_send((ENetSocket)socket, &address, &buffer, 1);
}

/* Reads one pending datagram into `data`. On success writes the sender's IP as text into `ip`
 * and its port to `port`. Returns the bytes received, 0 when nothing is pending, -1 on error. */
KATSA_EXPORT int knet_lan_receive(int socket, void* data, size_t capacity, char* ip,
                                  size_t ipSize, int* port) {
    ENetAddress address;
    ENetBuffer buffer;
    buffer.data = data;
    buffer.dataLength = capacity;
    int received = enet_socket_receive((ENetSocket)socket, &address, &buffer, 1);
    if (received > 0) {
        enet_address_get_host_ip(&address, ip, ipSize);
        *port = address.port;
    }
    return received;
}
