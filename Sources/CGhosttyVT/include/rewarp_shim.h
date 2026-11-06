#ifndef REWARP_SHIM_H
#define REWARP_SHIM_H

#include <ghostty/vt.h>
#include <stdint.h>
#include <sys/types.h>

/// Used by token handoff outside the fork/exec path. Checks the kernel-reported
/// parent and executable path; the requesting client supplies neither value.
int rewarp_process_is_child_executable(pid_t child, pid_t parent, const char *path);

/// Starts `path` on a new PTY. Returns the master fd, or -1 with errno set.
/// fork is unavailable from Swift, so this has to live in C: between fork and
/// exec the child may only call async-signal-safe functions.
int rewarp_pty_spawn(const char *path,
                     char *const argv[],
                     char *const envp[],
                     const char *cwd,
                     uint16_t cols,
                     uint16_t rows,
                     uint16_t width_px,
                     uint16_t height_px,
                     pid_t *out_pid);

/// Applies a new window size, which also signals SIGWINCH to the foreground job.
int rewarp_pty_resize(int fd,
                      uint16_t cols,
                      uint16_t rows,
                      uint16_t width_px,
                      uint16_t height_px);

#endif
