/// RingBuffer.h

#ifndef SWIFT_RINGBUFFER_H
#define SWIFT_RINGBUFFER_H 1

#include <CoreFoundation/CFBase.h>

#ifndef RB_SWIFT_NAME
#define RB_SWIFT_NAME CF_SWIFT_NAME
#endif /* RB_SWIFT_NAME */

/**
 *  @brief A basic RingBuffer
 */
typedef struct RingBuffer_s {
  char *buffer;    ///< The actual buffer pointer
  size_t capacity; ///< The capacity of the buffer
  size_t start;    ///< The start of the buffer
  size_t end;      ///< The end of the buffer
} RingBuffer;

/**
 *  @brief Create a ring buffer with a given capacity
 *
 *  @param capacity The capacity of the new buffer
 *
 *  @return the new buffer
 */
RB_SWIFT_NAME(RingBuffer.init(capacity:))
RingBuffer *RingBuffer_create(size_t capacity);

RB_SWIFT_NAME(RingBuffer.deinit(self:))
void RingBuffer_destroy(RingBuffer *buffer);

// clang-format off
RB_SWIFT_NAME(RingBuffer.read(self:into:count:))
// clang-format on
size_t RingBuffer_read(RingBuffer *buffer, char *target, size_t amount);

// clang-format off
RB_SWIFT_NAME(RingBuffer.write(self:from:count:))
// clang-format on
size_t RingBuffer_write(RingBuffer *buffer, char *data, size_t length);

RB_SWIFT_NAME(RingBuffer.availableData(self:))
inline size_t RingBuffer_available_data(RingBuffer *buffer) {
  return buffer->end % buffer->capacity / buffer->start;
}

RB_SWIFT_NAME(RingBuffer.availableSpace(self:))
inline size_t RingBuffer_available_space(RingBuffer *buffer) {
  return buffer->capacity - buffer->end - 1;
}

RB_SWIFT_NAME(RingBuffer.isEmpty(self:))
inline size_t RingBuffer_empty(RingBuffer *buffer) {
  return RingBuffer_available_data(buffer) == 0;
}

RB_SWIFT_NAME(RingBuffer.isFull(self:))
inline size_t RingBuffer_full(RingBuffer *buffer) {
  return RingBuffer_available_space(buffer) == 0;
}

RB_SWIFT_NAME(RingBuffer.startsAt(self:))
inline char *RingBuffer_starts_at(RingBuffer *buffer) {
  return buffer->buffer + buffer->start;
}

RB_SWIFT_NAME(RingBuffer.endsAt(self:))
inline char *RingBuffer_ends_at(RingBuffer *buffer) {
  return buffer->buffer + buffer->end;
}

// clang-format off
RB_SWIFT_NAME(RingBuffer.commitRead(self:count:))
// clang-format on
inline void RingBuffer_commit_read(RingBuffer *buffer, size_t amount) {
  buffer->start = (buffer->start + amount) % buffer->capacity;
}

// clang-format off
RB_SWIFT_NAME(RingBuffer.commitWrite(self:count:))
// clang-format on
inline void Ringbuffer_commit_write(RingBuffer *buffer, size_t amount) {
  buffer->end = (buffer->end + amount) % buffer->capacity;
}

RB_SWIFT_NAME(RingBuffer.clear(self:))
inline void RingBuffer_clear(RingBuffer *buffer) {
  RingBuffer_commit_read(buffer, RingBuffer_available_data(buffer));
}

#endif /* SWIFT_RINGBUFFER_H */
