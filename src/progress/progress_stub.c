#include <moonbit.h>

#include <stdio.h>

MOONBIT_FFI_EXPORT
void indexion_progress_eprint(const char *bytes, int32_t len) {
  if (bytes != NULL && len > 0) {
    fwrite(bytes, 1, (size_t)len, stderr);
  }
}

MOONBIT_FFI_EXPORT
void indexion_progress_eflush(void) {
  fflush(stderr);
}
