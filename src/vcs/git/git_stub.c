#include <moonbit.h>

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifndef _WIN32
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

static char *indexion_reconcile_copy_cstr(const char *src, int32_t len) {
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

#ifndef _WIN32
static const char *indexion_reconcile_git_executable(void) {
  static const char *candidates[] = {
      "/usr/bin/git",
      "/usr/local/bin/git",
      "/opt/homebrew/bin/git",
      NULL,
  };
  for (size_t i = 0; candidates[i] != NULL; i++) {
    if (access(candidates[i], X_OK) == 0) {
      return candidates[i];
    }
  }
  return NULL;
}

static void indexion_reconcile_exec_git(char *const argv[]) {
  const char *git_path = argv[0];
  if (git_path != NULL && git_path[0] == '/') {
    execv(git_path, argv);
  }
}

static int indexion_reconcile_wait_child(pid_t pid) {
  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) {
      return -1;
    }
  }
  if (!WIFEXITED(status)) {
    return -1;
  }
  return WEXITSTATUS(status);
}

static int indexion_reconcile_run_git(
    char *const argv[],
    bool capture_stdout,
    bool silence_stdout,
    char **output,
    size_t *output_len) {
  int pipe_fds[2] = {-1, -1};
  if (capture_stdout) {
    if (pipe(pipe_fds) != 0) {
      return -1;
    }
  }

  pid_t pid = fork();
  if (pid < 0) {
    if (capture_stdout) {
      close(pipe_fds[0]);
      close(pipe_fds[1]);
    }
    return -1;
  }

  if (pid == 0) {
    if (capture_stdout) {
      close(pipe_fds[0]);
      if (dup2(pipe_fds[1], STDOUT_FILENO) < 0) {
        _exit(127);
      }
      close(pipe_fds[1]);
    } else if (silence_stdout) {
      int devnull = open("/dev/null", O_WRONLY);
      if (devnull >= 0) {
        dup2(devnull, STDOUT_FILENO);
        close(devnull);
      }
    }

    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) {
      dup2(devnull, STDERR_FILENO);
      close(devnull);
    }

    indexion_reconcile_exec_git(argv);
    _exit(127);
  }

  if (capture_stdout) {
    close(pipe_fds[1]);
    size_t capacity = 4096;
    size_t length = 0;
    char *buffer = (char *)malloc(capacity);
    if (buffer == NULL) {
      close(pipe_fds[0]);
      (void)indexion_reconcile_wait_child(pid);
      return -1;
    }

    while (1) {
      if (length == capacity) {
        size_t new_capacity = capacity * 2;
        char *new_buffer = (char *)realloc(buffer, new_capacity);
        if (new_buffer == NULL) {
          free(buffer);
          close(pipe_fds[0]);
          (void)indexion_reconcile_wait_child(pid);
          return -1;
        }
        buffer = new_buffer;
        capacity = new_capacity;
      }
      ssize_t bytes_read = read(pipe_fds[0], buffer + length, capacity - length);
      if (bytes_read < 0) {
        if (errno == EINTR) {
          continue;
        }
        free(buffer);
        close(pipe_fds[0]);
        (void)indexion_reconcile_wait_child(pid);
        return -1;
      }
      if (bytes_read == 0) {
        break;
      }
      length += (size_t)bytes_read;
    }

    close(pipe_fds[0]);
    if (output != NULL) {
      *output = buffer;
    } else {
      free(buffer);
    }
    if (output_len != NULL) {
      *output_len = length;
    }
  }

  return indexion_reconcile_wait_child(pid);
}

static int indexion_reconcile_parse_int64(
    const char *text,
    size_t len,
    int64_t *value) {
  if (text == NULL || value == NULL) {
    return -1;
  }
  size_t start = 0;
  while (start < len &&
         (text[start] == ' ' || text[start] == '\n' || text[start] == '\r' ||
          text[start] == '\t')) {
    start++;
  }
  if (start >= len) {
    return -1;
  }
  int64_t result = 0;
  bool seen_digit = false;
  for (size_t i = start; i < len; i++) {
    char ch = text[i];
    if (ch >= '0' && ch <= '9') {
      seen_digit = true;
      result = result * 10 + (int64_t)(ch - '0');
      continue;
    }
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
      break;
    }
    return -1;
  }
  if (!seen_digit) {
    return -1;
  }
  *value = result;
  return 0;
}
#endif

MOONBIT_FFI_EXPORT
int32_t indexion_git_is_repo(const char *root, int32_t root_len) {
#ifdef _WIN32
  (void)root;
  (void)root_len;
  return 0;
#else
  const char *git_path = indexion_reconcile_git_executable();
  if (git_path == NULL) {
    return 0;
  }
  char *root_cstr = indexion_reconcile_copy_cstr(root, root_len);
  if (root_cstr == NULL) {
    return 0;
  }
  char *const argv[] = {
      (char *)git_path,
      "-C",
      root_cstr,
      "rev-parse",
      "--is-inside-work-tree",
      NULL,
  };
  int exit_code =
      indexion_reconcile_run_git(argv, false, true, NULL, NULL);
  free(root_cstr);
  return exit_code == 0 ? 1 : 0;
#endif
}

MOONBIT_FFI_EXPORT
int32_t indexion_git_status_dirty(
    const char *root,
    int32_t root_len,
    const char *path,
    int32_t path_len) {
#ifdef _WIN32
  (void)root;
  (void)root_len;
  (void)path;
  (void)path_len;
  return 0;
#else
  const char *git_path = indexion_reconcile_git_executable();
  if (git_path == NULL) {
    return 0;
  }
  char *root_cstr = indexion_reconcile_copy_cstr(root, root_len);
  char *path_cstr = indexion_reconcile_copy_cstr(path, path_len);
  if (root_cstr == NULL || path_cstr == NULL) {
    free(root_cstr);
    free(path_cstr);
    return 0;
  }

  char *output = NULL;
  size_t output_len = 0;
  char *const argv[] = {
      (char *)git_path,
      "-C",
      root_cstr,
      "status",
      "--porcelain=v1",
      "--",
      path_cstr,
      NULL,
  };
  int exit_code =
      indexion_reconcile_run_git(argv, true, false, &output, &output_len);
  free(root_cstr);
  free(path_cstr);
  if (exit_code != 0) {
    free(output);
    return 0;
  }
  int32_t dirty = output_len > 0 ? 1 : 0;
  free(output);
  return dirty;
#endif
}

MOONBIT_FFI_EXPORT
int64_t indexion_git_last_commit_seconds(
    const char *root,
    int32_t root_len,
    const char *path,
    int32_t path_len) {
#ifdef _WIN32
  (void)root;
  (void)root_len;
  (void)path;
  (void)path_len;
  return -1;
#else
  const char *git_path = indexion_reconcile_git_executable();
  if (git_path == NULL) {
    return -1;
  }
  char *root_cstr = indexion_reconcile_copy_cstr(root, root_len);
  char *path_cstr = indexion_reconcile_copy_cstr(path, path_len);
  if (root_cstr == NULL || path_cstr == NULL) {
    free(root_cstr);
    free(path_cstr);
    return -1;
  }

  char *output = NULL;
  size_t output_len = 0;
  char *const argv[] = {
      (char *)git_path,
      "-C",
      root_cstr,
      "log",
      "-1",
      "--format=%ct",
      "--",
      path_cstr,
      NULL,
  };
  int exit_code =
      indexion_reconcile_run_git(argv, true, false, &output, &output_len);
  free(root_cstr);
  free(path_cstr);
  if (exit_code != 0 || output == NULL) {
    free(output);
    return -1;
  }

  int64_t seconds = -1;
  if (indexion_reconcile_parse_int64(output, output_len, &seconds) != 0) {
    free(output);
    return -1;
  }
  free(output);
  return seconds;
#endif
}

