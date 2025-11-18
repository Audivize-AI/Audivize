//
//  Linspace.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/27/25.
//

import Foundation
import Accelerate


extension Utils.ML {
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(from start: Float, through end: Float, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Float(count - 1)

        return vDSP.ramp(
            withInitialValue: start,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(from start: Float, to end: Float, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Float(count)

        return vDSP.ramp(
            withInitialValue: start,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(past start: Float, through end: Float, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Float(count)

        return vDSP.ramp(
            withInitialValue: start + step,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(past start: Float, to end: Float, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Float(count + 1)

        return vDSP.ramp(
            withInitialValue: start + step,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(from start: Double, through end: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Double(count - 1)

        return vDSP.ramp(
            withInitialValue: start,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(from start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Double(count)

        return vDSP.ramp(
            withInitialValue: start,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(past start: Double, through end: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Double(count)

        return vDSP.ramp(
            withInitialValue: start + step,
            increment: step,
            count: count
        )
    }
    
    /**
     Creates a linearly spaced vector, equivalent to numpy.linspace.
     - Parameters:
        - start: The starting value of the sequence.
        - end: The ending value of the sequence.
        - count: The number of samples to generate.
     - Returns: An array of `count` evenly-spaced samples from `start` to `end`.
     */
    static func linspace(past start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        
        let step = (end - start) / Double(count + 1)

        return vDSP.ramp(
            withInitialValue: start + step,
            increment: step,
            count: count
        )
    }
}
