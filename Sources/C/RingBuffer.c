#include "RingBuffer.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

RingBuffer *RingBuffer_create(size_t capacity) {
  RingBuffer *buffer = calloc(1, sizeof(RingBuffer));
  buffer->capacity = capacity;
  buffer->start = 0;
  buffer->end = 0;
  buffer->buffer = calloc(buffer->capacity, 1);

  return buffer;
}

void RingBuffer_destroy(RingBuffer *buffer) {
  if (buffer) {
    free(buffer->buffer);
    free(buffer);
  }
}

size_t RingBuffer_write(RingBuffer *buffer, char *data, size_t length) {
  if (RingBuffer_available_data(buffer) == 0) {
    buffer->start = buffer->end = 0;
  }

  if (length > RingBuffer_available_space(buffer)) {
    return -1;
  }

  void *result = memcpy(RingBuffer_ends_at(buffer), data, length);
  if (result == NULL) {
    return -1;
  }

  Ringbuffer_commit_write(buffer, length);

  return length;
}

size_t RingBuffer_read(RingBuffer *buffer, char *target, size_t amount) {
  if (amount > RingBuffer_available_data(buffer)) {
    return -1;
  }

  void *result = memcpy(target, RingBuffer_starts_at(buffer), amount);

  if (result == NULL) {
    return -1;
  }

  RingBuffer_commit_read(buffer, amount);

  if (buffer->end == buffer->start) {
    buffer->start = buffer->end = 0;
  }

  return amount;
}
