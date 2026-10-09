#ifndef PERSIST_FAULT_H
#define PERSIST_FAULT_H
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <unistd.h>
size_t audit_fwrite(const void *, size_t, size_t, FILE *);
int audit_fflush(FILE *);
int audit_fsync(int);
int audit_fclose(FILE *);
int audit_rename(const char *, const char *);
#define fwrite audit_fwrite
#define fflush audit_fflush
#define fsync audit_fsync
#define fclose audit_fclose
#define rename audit_rename
#endif
