#include "rewarp_shim.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
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
    for (int fd = 3; fd < 256; fd++) close(fd);

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
