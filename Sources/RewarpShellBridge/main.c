#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

// Shell adapters pass credentials and values on stdin, never in argv or the
// environment. Encoding and framing are shared by every supported shell.
static int encode(void) {
  int byte;
  while ((byte = getchar()) != EOF) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || (byte != 0 && strchr("._~/-", byte))) {
      if (putchar(byte) == EOF) return 1;
    } else if (printf("%%%02X", (unsigned int)byte) < 0) {
      return 1;
    }
  }
  return ferror(stdin) || ferror(stdout);
}

static int report(const char *key) {
  if (!*key) return 2;
  for (const char *p = key; *p; p++) if (*p < 'a' || *p > 'z') return 2;
  char token[129];
  if (!fgets(token, sizeof(token), stdin)) return 2;
  size_t length = strlen(token);
  if (length < 2 || token[length - 1] != '\n') return 2;
  token[--length] = '\0';
  for (size_t i = 0; i < length; i++) {
    unsigned char c = (unsigned char)token[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '-')) return 2;
  }
  if (printf("\033]7701;%s=%s;", key, token) < 0 || encode()) return 1;
  return putchar('\a') == EOF || fflush(stdout) == EOF;
}

// The app authenticates the caller and allows this helper only once during a
// shell's bootstrap. The credential is captured by the parent shell on stdout.
static int token(const char *path) {
  struct sockaddr_un address = {0};
  if (strlen(path) >= sizeof(address.sun_path)) return 2;
  address.sun_family = AF_UNIX;
#ifdef __APPLE__
  address.sun_len = sizeof(address);
#endif
  strcpy(address.sun_path, path);
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return 1;
  struct timeval timeout = {.tv_sec = 2};
  if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0 ||
      connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
    close(fd);
    return 1;
  }
  char line[129];
  size_t count = 0;
  while (count < sizeof(line) - 1) {
    ssize_t got = read(fd, line + count, 1);
    if (got < 0 && errno == EINTR) continue;
    if (got != 1) { close(fd); return 1; }
    if (line[count++] == '\n') {
      close(fd);
      return fwrite(line, 1, count, stdout) != count || fflush(stdout) == EOF;
    }
  }
  close(fd);
  return 2;
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "encode")) return encode();
  if (argc == 3 && !strcmp(argv[1], "report")) return report(argv[2]);
  if (argc == 3 && !strcmp(argv[1], "token")) return token(argv[2]);
  fputs("usage: RewarpShellBridge encode | report KEY | token SOCKET\n", stderr);
  return 2;
}
