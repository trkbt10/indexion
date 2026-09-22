#include "buffer.h"

#include <stdlib.h>
#include <string.h>

AppBuffer app_buffer_create(size_t capacity) {
    AppBuffer buffer;
    buffer.data = (unsigned char*)malloc(capacity);
    buffer.size = 0;
    buffer.capacity = capacity;
    return buffer;
}

int app_buffer_append(AppBuffer* buffer, const unsigned char* bytes, size_t count) {
    if (buffer->size + count > buffer->capacity) {
        return 0;
    }
    memcpy(buffer->data + buffer->size, bytes, count);
    buffer->size += count;
    return 1;
}

void app_buffer_destroy(AppBuffer* buffer) {
    free(buffer->data);
    buffer->data = NULL;
    buffer->size = 0;
    buffer->capacity = 0;
}
