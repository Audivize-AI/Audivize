//
//  ASDModelPool.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/30/25.
//

import Foundation
import CoreML


protocol MLWrapper: AnyObject, Sendable {}

extension Utils.ML {
    /// An async-safe pool of Core ML models.
    actor ModelPool<M: MLWrapper> {
        private var available: [M]
        private var waitingContinuations: [CheckedContinuation<M, Never>] = []
        
        /// Initialize with N copies of your compiled model.
        init(count: Int, constructor makeModel: () throws -> M) throws {
            assert(count > 0)
            self.available = try (0..<count).map { _ in
                try makeModel()
            }
        }
        
        /// Borrow a model; suspends if none are free.
        func borrow() async -> M {
            if let m = available.popLast() {
                return m
            }
            return await withCheckedContinuation { cont in
                waitingContinuations.append(cont)
            }
        }
        
        /// Return a model back into the pool.
        func `return`(_ model: M) {
            if let cont = waitingContinuations.first {
                waitingContinuations.removeFirst()
                cont.resume(returning: model)
            } else {
                available.append(model)
            }
        }
        
        /// Convenience: borrow → run your work → auto-return
        func withModel<T: Sendable>(_ body: (M) async throws -> T) async rethrows -> T {
            let m = await borrow()
            defer { Task { self.return(m) } }
            return try await body(m)
        }
    }
}
