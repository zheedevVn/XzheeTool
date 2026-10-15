//
//  XTool+Version.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

import CXKit

extension XTool {
    public static let version = String(cString: xtl_version())
}
