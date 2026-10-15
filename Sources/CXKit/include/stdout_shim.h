//
//  stdout_shim.h
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

#include <stdio.h>

inline static FILE *get_stdout() {
    return stdout;
}
