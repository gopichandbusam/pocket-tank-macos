#include "progression.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    tank_t tank;
    tank_init(&tank, 12345);
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "save")) {
        progression_fresh(&tank);
        tank_set_name(&tank, 0, "ruby");
        return progression_save(&tank) ? 0 : 1;
    }
    if (!strcmp(argv[1], "load")) {
        progression_boot(&tank);
        printf("fish=%d name=%s\n", tank.n_fish, tank.fish[0].name);
        return tank.n_fish >= 2 && tank.n_fish <= N_FISH_MAX ? 0 : 1;
    }
    return 2;
}
