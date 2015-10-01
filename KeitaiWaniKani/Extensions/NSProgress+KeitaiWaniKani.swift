//
//  NSProgress+KeitaiWaniKani.swift
//  KeitaiWaniKani
//
//  Copyright © 2015 Chris Laverty. All rights reserved.
//

import Foundation

extension NSProgress {
    var finished: Bool {
        let completed = self.completedUnitCount
        let total = self.totalUnitCount
        return (completed >= total && total > 0 && completed > 0) || (completed > 0 && total == 0)
    }
}
