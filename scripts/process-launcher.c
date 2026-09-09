#include <unistd.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc < 2 || setpgid(0, 0) != 0) return 126;
    execv(argv[1], argv + 1);
    perror("execv"); return 127;
}
