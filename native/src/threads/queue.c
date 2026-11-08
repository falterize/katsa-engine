/*
 * katsa_threads / queue: a FIFO of byte messages shared by two threads.
 *
 * Each actor has two: the inbox (main thread -> worker) and the outbox (worker -> main thread).
 * Any number of threads may push; receivers take messages in order.
 */
#include <stdlib.h>

#include "threads.h"

void queue_init(KQueue* queue) {
    queue->head = NULL;
    queue->tail = NULL;
    queue->count = 0;
    mutex_init(&queue->mutex);
    cond_init(&queue->cond);
}

void queue_destroy(KQueue* queue) {
    KMsg* message = queue->head;
    while (message) {
        KMsg* next = message->next;
        free(message);
        message = next;
    }
    queue->head = NULL;
    queue->tail = NULL;
    queue->count = 0;
    mutex_destroy(&queue->mutex);
    cond_destroy(&queue->cond);
}

void queue_push(KQueue* queue, KMsg* message) {
    message->next = NULL;
    mutex_lock(&queue->mutex);
    if (queue->tail) {
        queue->tail->next = message;
    } else {
        queue->head = message;
    }
    queue->tail = message;
    queue->count += 1;
    cond_signal(&queue->cond);
    mutex_unlock(&queue->mutex);
}

KMsg* queue_pop(KQueue* queue, int timeoutMs, const int* stop) {
    mutex_lock(&queue->mutex);
    /* `stop` is read under the mutex. kt_request_stop sets it before taking this mutex to signal,
     * so either this check sees it, or the signal arrives after the wait has started: a stop
     * request can never be missed by a receiver that is about to block. */
    int stopping = stop && __atomic_load_n(stop, __ATOMIC_ACQUIRE);
    if (!queue->head && timeoutMs != 0 && !stopping) {
        cond_wait(&queue->cond, &queue->mutex, timeoutMs);
    }
    KMsg* message = queue->head;
    if (message) {
        queue->head = message->next;
        if (!queue->head) {
            queue->tail = NULL;
        }
        queue->count -= 1;
    }
    mutex_unlock(&queue->mutex);
    return message;
}

int queue_count(KQueue* queue) {
    mutex_lock(&queue->mutex);
    int count = queue->count;
    mutex_unlock(&queue->mutex);
    return count;
}
