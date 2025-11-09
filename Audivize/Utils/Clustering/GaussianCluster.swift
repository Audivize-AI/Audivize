//
//  GaussianCluster.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/28/25.
//

import Foundation
import Accelerate

struct Cluster {
    var id: UUID? = nil
    var count: Int = 0
    var sum: [Float]
    var centroid: [Float]
    var dims: Int { sum.count }
    
    func cosineDistance(to other: Cluster) -> Float {
        precondition(dims == other.dims)
        return 1 - vDSP.dot(centroid, other.centroid) / sqrt(vDSP.sumOfSquares(centroid) * vDSP.sumOfSquares(other.centroid))
    }
    
    func normalizedL2Distance(to other: Cluster) -> Float {
        precondition(dims == other.dims)
        return vDSP.l2Norm(
            vDSP.subtract(
                vDSP.unitVector(centroid),
                vDSP.unitVector(other.centroid)
            )
        )
    }
    
    func l2Distance(to other: Cluster) -> Float {
        precondition(dims == other.dims)
        return vDSP.l2Norm(vDSP.subtract(centroid, other.centroid))
    }
    
    static func += (lhs: inout Cluster, rhs: Cluster) {
        precondition(lhs.dims == rhs.dims)
        
        if lhs.id == nil {
            lhs.id = rhs.id
        }
        
        lhs.count += rhs.count
        vDSP.add(lhs.sum, rhs.sum, result: &lhs.sum)
        vDSP.multiply(1.0 / Float(lhs.count), lhs.sum, result: &lhs.centroid)
    }
    
    static func += (lhs: inout Cluster, rhs: [Float]) {
        precondition(lhs.dims == rhs.count)
        lhs.count += 1
        vDSP.add(lhs.sum, rhs, result: &lhs.sum)
        vDSP.multiply(1.0 / Float(lhs.count), lhs.sum, result: &lhs.centroid)
    }
}



extension vDSP {
    @inline(__always)
    static func l2Norm(_ vector: any AccelerateBuffer<Float>) -> Float {
        return sqrt(vDSP.sumOfSquares(vector))
    }
    
    @inline(__always)
    static func l2Norm(_ vector: any AccelerateBuffer<Double>) -> Double {
        return sqrt(vDSP.sumOfSquares(vector))
    }
    
    @inline(__always)
    static func unitVector(_ vector: any AccelerateBuffer<Float>) -> [Float] {
        return vDSP.multiply(1 / l2Norm(vector), vector)
    }
    
    @inline(__always)
    static func unitVector(_ vector: any AccelerateBuffer<Float>, result: inout some AccelerateMutableBuffer<Float>) {
        vDSP.multiply(1 / l2Norm(vector), vector, result: &result)
    }
    
    @inline(__always)
    static func unitVector(_ vector: any AccelerateBuffer<Double>) -> [Double] {
        return vDSP.multiply(1 / l2Norm(vector), vector)
    }
    
    static func unitVector(_ vector: any AccelerateBuffer<Double>, result: inout some AccelerateMutableBuffer<Double>) {
        vDSP.multiply(1 / l2Norm(vector), vector, result: &result)
    }
}
