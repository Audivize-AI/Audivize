//
//  ASDModelPool.swift
//  Audivize
//
//  Created by Benjamin Lee on 11/11/25.
//

import Foundation
@preconcurrency import CoreML

extension Pairing.ASD {
    actor ASDModelPool: Sendable {
        typealias ASDModel = ASDConfiguration.ASDModel
        typealias Model = ASDModel.Model
        typealias Input = ASDModel.Input
        
        private var available: [Model]
        private var waitingContinuations: [CheckedContinuation<Model, Never>] = []
        
        /// - Parameter count: Number of concurrently existing ASD model.
        public init(count: Int) throws {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            
            self.available = try (0..<count).map { _ in
                try .init(configuration: configuration)
            }
        }
        
        /// Borrow a model; suspends if none are free.
        /// - Returns: An ASD model
        public func borrow() async -> Model {
            if let model = available.popLast() {
                return model
            }
            return await withCheckedContinuation { cont in
                waitingContinuations.append(cont)
            }
        }
        
        /// Return a model back into the pool.
        /// - Parameter model: The model to put back
        public func reclaim(_ model: Model) {
            if let cont = waitingContinuations.first {
                waitingContinuations.removeFirst()
                cont.resume(returning: model)
            } else {
                available.append(model)
            }
        }
        
        /// Convenience: borrow → run your work → auto-return
        public func withModel<T: Sendable>(_ body: (Model) throws -> T) async rethrows -> T {
            let m = await borrow()
            defer { Task { self.reclaim(m) } }
            return try body(m)
        }
        
        /// Convenience: borrow → run your work → auto-return
        public func withModel<T: Sendable>(_ body: (Model) async throws -> T) async rethrows -> T {
            let m = await borrow()
            defer { Task { self.reclaim(m) } }
            return try await body(m)
        }
        
        /// Run an ASD model on an input and get the prediction
        public func runInference(on input: Input) async throws -> [Float] {
            return try await withModel { model in
                return try model.prediction(input: input).scoresShapedArray.scalars
            }
        }
    }
}
