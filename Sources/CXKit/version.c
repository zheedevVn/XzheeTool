//
//  version.c
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

#include "version.h"

const char *xtl_version(void) {
#ifdef XTOOL_VERSION
    return XTOOL_VERSION;
#else
    return "unversioned";
#endif
}
