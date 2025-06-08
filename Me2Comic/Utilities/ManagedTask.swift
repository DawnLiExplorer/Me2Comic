//
//  ManagedTask.swift
//  Me2Comic
//
//  Created by Me2 on 2025/6/6.
//

import Foundation

/// A wrapper class for Process that adds a unique identifier
class ManagedTask {
    /// The unique identifier for this task
    let id = UUID()

    /// The wrapped Process instance
    let process: Process

    /// Initialize with a Process instance
    /// - Parameter process: The Process to wrap
    init(process: Process) {
        self.process = process
    }
}
