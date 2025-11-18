import Foundation
import CoreML

extension Pairing.ASD {
    protocol ASDModelType {
        associatedtype Model
        associatedtype Input
        associatedtype Output
        static var videoLength: Int { get }
        static var minFrames: Int { get }
    }
    
    enum ASD25_AVA: ASDModelType {
        typealias Model = ASDVideoModel25_AVA
        typealias Input = ASDVideoModel25_AVAInput
        typealias Output = ASDVideoModel25_AVAOutput
        static let videoLength = 25
        static let minFrames = 12
    }
    
    enum ASD25_TalkSet: ASDModelType {
        typealias Model = ASDVideoModel25_TalkSet
        typealias Input = ASDVideoModel25_TalkSetInput
        typealias Output = ASDVideoModel25_TalkSetOutput
        static let videoLength = 25
        static let minFrames = 12
    }
    
    enum ASD50_AVA: ASDModelType {
        typealias Model = ASDVideoModel50_AVA
        typealias Input = ASDVideoModel50_AVAInput
        typealias Output = ASDVideoModel50_AVAOutput
        static let videoLength = 50
        static let minFrames = 12
    }
    
    enum ASD50_TalkSet: ASDModelType {
        typealias Model = ASDVideoModel50_TalkSet
        typealias Input = ASDVideoModel50_TalkSetInput
        typealias Output = ASDVideoModel50_TalkSetOutput
        static let videoLength = 50
        static let minFrames = 12
    }
}

extension ASDVideoModel25_TalkSetInput : @unchecked Sendable {}
extension ASDVideoModel25_TalkSetOutput : @unchecked Sendable {}
extension ASDVideoModel25_TalkSet: @unchecked Sendable {}

extension ASDVideoModel50_TalkSetInput : @unchecked Sendable {}
extension ASDVideoModel50_TalkSetOutput : @unchecked Sendable {}
extension ASDVideoModel50_TalkSet: @unchecked Sendable {}

extension ASDVideoModel25_AVAInput : @unchecked Sendable {}
extension ASDVideoModel25_AVAOutput : @unchecked Sendable {}
extension ASDVideoModel25_AVA: @unchecked Sendable {}

extension ASDVideoModel50_AVAInput : @unchecked Sendable {}
extension ASDVideoModel50_AVAOutput : @unchecked Sendable {}
extension ASDVideoModel50_AVA: @unchecked Sendable {}
