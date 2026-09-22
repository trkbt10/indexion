#ifndef APP_BUFFER_H
#define APP_BUFFER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A plain C byte buffer, consumed from both C and C++ translation units. */
typedef struct AppBuffer {
    unsigned char* data;
    size_t size;
    size_t capacity;
} AppBuffer;

AppBuffer app_buffer_create(size_t capacity);

int app_buffer_append(AppBuffer* buffer, const unsigned char* bytes, size_t count);

void app_buffer_destroy(AppBuffer* buffer);

#ifdef __cplusplus
}
#endif

#endif /* APP_BUFFER_H */
