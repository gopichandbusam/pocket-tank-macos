#define _POSIX_C_SOURCE 200809L
#include "progression.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fault(const char *name) {
    const char *value = getenv("AUDIT_WRITE_FAULT");
    return value && !strcmp(value, name);
}
size_t audit_fwrite(const void *p, size_t size, size_t count, FILE *f) {
    if (fault("interrupt")) _exit(77);
    if (fault("short")) {
        size_t n = fwrite(p, size, count / 2, f);
        errno = ENOSPC;
        return n;
    }
    return fwrite(p, size, count, f);
}
int audit_fflush(FILE *f) {
    if (fault("flush")) { errno = ENOSPC; return EOF; }
    return fflush(f);
}
int audit_fsync(int fd) {
    if (fault("sync")) { errno = EIO; return -1; }
    return fsync(fd);
}
int audit_fclose(FILE *f) {
    int result = fclose(f);
    if (fault("close")) { errno = EIO; return EOF; }
    return result;
}
int audit_rename(const char *from, const char *to) {
    if (fault("replace")) { errno = EACCES; return -1; }
    return rename(from, to);
}

int main(int argc, char **argv) {
    unsigned char data[1688];
    for (size_t i = 0; i < sizeof data; ++i) data[i] = (unsigned char)(i * 37 + 11);
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "save")) {
        errno = 0;
        bool ok = persist_port_save(data, sizeof data);
        printf("saved=%d errno=%d\n", ok, errno);
        return ok ? 0 : 1;
    }
    if (!strcmp(argv[1], "load")) {
        unsigned char loaded[1688]; size_t got = 0;
        bool ok = persist_port_load(loaded, sizeof loaded, &got);
        printf("loaded=%d bytes=%zu equal=%d\n", ok, got,
               ok && got == sizeof data && !memcmp(data, loaded, sizeof data));
        return ok ? 0 : 1;
    }
    return 2;
}
