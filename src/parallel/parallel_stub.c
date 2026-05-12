#include <moonbit.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#else
#include <process.h>
#include <windows.h>
#endif

static char *indexion_par_copy_cstr(const char *src, int32_t len) {
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

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_available(void) {
#ifdef _WIN32
  return 0;
#else
  return 1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_fork(void) {
#ifdef _WIN32
  return -1;
#else
  return (int32_t)fork();
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_waitpid(int32_t pid) {
#ifdef _WIN32
  (void)pid;
  return -1;
#else
  int status;
  while (waitpid((pid_t)pid, &status, 0) < 0) {
    if (errno != EINTR) {
      return -1;
    }
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
void indexion_parallel_exit(int32_t code) {
#ifndef _WIN32
  _exit(code);
#else
  exit(code);
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_getpid(void) {
#ifdef _WIN32
  return (int32_t)_getpid();
#else
  return (int32_t)getpid();
#endif
}

MOONBIT_FFI_EXPORT
void indexion_parallel_flush_stdio(void) {
  fflush(stdout);
  fflush(stderr);
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_mkdir(const char *path, int32_t path_len) {
#ifdef _WIN32
  (void)path;
  (void)path_len;
  return -1;
#else
  char *buf = indexion_par_copy_cstr(path, path_len);
  if (buf == NULL) {
    return -1;
  }
  int ret = mkdir(buf, 0700);
  free(buf);
  if (ret == 0 || errno == EEXIST) {
    return 0;
  }
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_unlink(const char *path, int32_t path_len) {
#ifdef _WIN32
  (void)path;
  (void)path_len;
  return -1;
#else
  char *buf = indexion_par_copy_cstr(path, path_len);
  if (buf == NULL) {
    return -1;
  }
  int ret = unlink(buf);
  free(buf);
  return ret;
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_rmdir(const char *path, int32_t path_len) {
#ifdef _WIN32
  (void)path;
  (void)path_len;
  return -1;
#else
  char *buf = indexion_par_copy_cstr(path, path_len);
  if (buf == NULL) {
    return -1;
  }
  int ret = rmdir(buf);
  free(buf);
  return ret;
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_parallel_cpu_count(void) {
#ifdef _WIN32
  return 1;
#else
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n > 0 ? (int32_t)n : 1;
#endif
}

