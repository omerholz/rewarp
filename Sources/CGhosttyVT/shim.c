#include "rewarp_shim.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

int rewarp_pty_spawn(const char *path,
                     char *const argv[],
                     char *const envp[],
                     const char *cwd,
                     uint16_t cols,
                     uint16_t rows,
                     uint16_t width_px,
                     uint16_t height_px,
                     pid_t *out_pid) {
  // Resolve the ceiling before fork: getrlimit/sysctl need not be safe in the
  // child. The soft limit can be lower than descriptors already open, so use
  // the kernel ceiling as well as the finite hard limit.
  int fd_limit = 0;
  size_t limit_size = sizeof(fd_limit);
  int mib[] = {CTL_KERN, KERN_MAXFILESPERPROC};
  if (sysctl(mib, 2, &fd_limit, &limit_size, NULL, 0) < 0) return -1;
  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) < 0) return -1;
  if (limit.rlim_max != RLIM_INFINITY && limit.rlim_max > (rlim_t)fd_limit &&
      limit.rlim_max <= INT_MAX) fd_limit = (int)limit.rlim_max;
  if (fd_limit < 3) { errno = EINVAL; return -1; }

  struct winsize size = {
      .ws_row = rows,
      .ws_col = cols,
      .ws_xpixel = width_px,
      .ws_ypixel = height_px,
  };

  int master = -1;
  pid_t pid = forkpty(&master, NULL, NULL, &size);
  if (pid < 0) return -1;

  if (pid == 0) {
    // Only async-signal-safe calls from here until exec.
    if (cwd != NULL) (void)chdir(cwd);

    // Without IUTF8 the kernel's line editor erases one byte at a time, which
    // corrupts multibyte characters on backspace in cooked mode.
    struct termios tio;
    if (tcgetattr(STDIN_FILENO, &tio) == 0) {
      tio.c_iflag |= IUTF8;
      (void)tcsetattr(STDIN_FILENO, TCSANOW, &tio);
    }

    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
    for (int sig = 1; sig < NSIG; sig++) {
      if (sig != SIGKILL && sig != SIGSTOP) signal(sig, SIG_DFL);
    }

    // The app's own descriptors must not leak into the user's shell.
    for (int fd = 3; fd < fd_limit; fd++) close(fd);

    execve(path, argv, envp);
    _exit(127);
  }

  (void)fcntl(master, F_SETFD, FD_CLOEXEC);
  *out_pid = pid;
  return master;
}

int rewarp_pty_resize(int fd,
                      uint16_t cols,
                      uint16_t rows,
                      uint16_t width_px,
                      uint16_t height_px) {
  struct winsize size = {
      .ws_row = rows,
      .ws_col = cols,
      .ws_xpixel = width_px,
      .ws_ypixel = height_px,
  };
  return ioctl(fd, TIOCSWINSZ, &size);
}
