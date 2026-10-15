//
//  Stdlib+Utils.swift
//  xtool
//
//  Created by Hồ Đức Minh (zheedevVn).
//  Copyright © 2026 Hồ Đức Minh (zheedevVn). All rights reserved.
//

package struct StringError: Error, CustomStringConvertible {
    package var description: String
    package init(_ description: String) {
        self.description = description
    }
}
