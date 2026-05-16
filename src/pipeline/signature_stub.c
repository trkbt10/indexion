#include <moonbit.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32
#include <windows.h>
#endif

// Copy a non-null-terminated byte run into an owned C string.
// Returns NULL on allocation failure.
static char *indexion_sig_copy_cstr(const char *src, int32_t len) {
  if (src == NULL || len < 0) {
    return NULL;
  }
  char *dst = (char *)malloc((size_t)len + 1);
  if (dst == NULL) {
    return NULL;
  }
  if (len > 0) {
    memcpy(dst, src, (size_t)len);
  }
  dst[len] = '\0';
  return dst;
}

// Fill `out[0]` with mtime in nanoseconds since the unix epoch and `out[1]`
// with the file size in bytes. Follows symlinks (matches stat()).
// Returns 1 if the path exists and was stat'd successfully, 0 otherwise.
MOONBIT_FFI_EXPORT
int32_t indexion_signature_stat(const char *path, int32_t path_len,
                                 int64_t *out) {
  if (out == NULL) {
    return 0;
  }
  out[0] = 0;
  out[1] = 0;
  char *cpath = indexion_sig_copy_cstr(path, path_len);
  if (cpath == NULL) {
    return 0;
  }
  struct stat st;
  int rc = stat(cpath, &st);
  free(cpath);
  if (rc != 0) {
    return 0;
  }
#if defined(__APPLE__)
  out[0] = (int64_t)st.st_mtimespec.tv_sec * 1000000000LL +
           (int64_t)st.st_mtimespec.tv_nsec;
#elif defined(_WIN32)
  // Windows: stat returns time_t in seconds. Nanosecond precision requires
  // GetFileAttributesEx, but for change-detection seconds are sufficient.
  out[0] = (int64_t)st.st_mtime * 1000000000LL;
#else
  out[0] = (int64_t)st.st_mtim.tv_sec * 1000000000LL +
           (int64_t)st.st_mtim.tv_nsec;
#endif
  out[1] = (int64_t)st.st_size;
  return 1;
}
