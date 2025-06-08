//
//  ThreadSafeArray.swift
//  Me2Comic
//
//  Created by Me2 on 2025/6/6.
//

import Foundation

/// Thread-safe array implementation that provides safe access from multiple threads
class ThreadSafeArray<T> {
    private var array = [T]()
    private let queue: DispatchQueue
    
    /// Initialize with a specific dispatch queue for synchronization
    /// - Parameter queue: The dispatch queue to use for synchronization
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    /// Append a single element to the array in a thread-safe manner
    /// - Parameter element: The element to append
    func append(_ element: T) {
        queue.sync {
            array.append(element)
        }
    }
    
    /// Append multiple elements to the array in a thread-safe manner
    /// - Parameter elements: The elements to append
    func append(contentsOf elements: [T]) {
        queue.sync {
            array.append(contentsOf: elements)
        }
    }
    
    /// Get all elements from the array in a thread-safe manner
    /// - Returns: A copy of all elements in the array
    func getAll() -> [T] {
        var result = [T]()
        queue.sync {
            result = array
        }
        return result
    }
    
    /// Check if the array is empty in a thread-safe manner
    /// - Returns: True if the array is empty, false otherwise
    var isEmpty: Bool {
        var empty = true
        queue.sync {
            empty = array.isEmpty
        }
        return empty
    }
    
    /// Get the count of elements in the array in a thread-safe manner
    /// - Returns: The number of elements in the array
    var count: Int {
        var result = 0
        queue.sync {
            result = array.count
        }
        return result
    }
}
