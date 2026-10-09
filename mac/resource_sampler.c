#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/proc_info.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void on_signal(int sig) { (void)sig; stopping = 1; }
static uint64_t monotonic_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: %s PID PHASE SECONDS CSV\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    long parsed_pid = strtol(argv[1], &end, 10);
    if (!end || *end || parsed_pid <= 0 || parsed_pid > 0x7fffffff) return 2;
    int pid = (int)parsed_pid;
    const char *phase = argv[2];
    long seconds = strtol(argv[3], &end, 10);
    if (!end || *end || seconds < 1 || seconds > 3600) return 2;
    FILE *out = fopen(argv[4], "w");
    if (!out) { perror("fopen"); return 1; }
    signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
    mach_timebase_info_data_t timebase = {0};
    kern_return_t timebase_rc = mach_timebase_info(&timebase);
    if (timebase_rc != KERN_SUCCESS || timebase.numer == 0 || timebase.denom == 0) {
        fprintf(stderr, "mach_timebase_info failed: %d\n", timebase_rc);
        fclose(out); return 1;
    }
    fprintf(out, "timestamp_monotonic_ns,phase,pid,user_cpu_mach_ticks,system_cpu_mach_ticks,timebase_numer,timebase_denom,phys_footprint_bytes,resident_bytes,energy_nj,penergy_nj\n");
    fflush(out);
    uint64_t process_start_sec = 0;
    uint64_t process_start_usec = 0;
    int have_process_identity = 0;
    for (long i = 0; i < seconds && !stopping; i++) {
        struct proc_bsdinfo identity;
        memset(&identity, 0, sizeof(identity));
        int identity_size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &identity, sizeof(identity));
        if (identity_size != sizeof(identity)) {
            fprintf(stderr, "process %d is no longer live (proc_pidinfo returned %d)\n", pid, identity_size);
            fclose(out); return 3;
        }
        if (identity.pbi_pid != (uint32_t)pid) {
            fprintf(stderr, "process identity mismatch for PID %d\n", pid);
            fclose(out); return 3;
        }
        if (!have_process_identity) {
            process_start_sec = identity.pbi_start_tvsec;
            process_start_usec = identity.pbi_start_tvusec;
            have_process_identity = 1;
        } else if (identity.pbi_start_tvsec != process_start_sec ||
                   identity.pbi_start_tvusec != process_start_usec) {
            fprintf(stderr, "PID %d was reused by a different process; stopping sample\n", pid);
            fclose(out); return 3;
        }
        struct rusage_info_v6 usage;
        memset(&usage, 0, sizeof(usage));
        if (proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, (rusage_info_t *)&usage) != 0) {
            fprintf(stderr, "proc_pid_rusage(%d): %s\n", pid, strerror(errno));
            fclose(out); return 1;
        }
        fprintf(out, "%" PRIu64 ",%s,%d,%" PRIu64 ",%" PRIu64 ",%u,%u,%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 "\n",
                monotonic_ns(), phase, pid, usage.ri_user_time, usage.ri_system_time,
                timebase.numer, timebase.denom, usage.ri_phys_footprint, usage.ri_resident_size,
                usage.ri_energy_nj, usage.ri_penergy_nj);
        fflush(out);
        struct timespec delay = { .tv_sec = 1, .tv_nsec = 0 };
        while (nanosleep(&delay, &delay) != 0 && errno == EINTR && !stopping) {}
    }
    fclose(out);
    return 0;
}
