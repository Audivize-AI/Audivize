//
//  FaceSpeechDatabase.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 8/21/25.
//

import Foundation

extension ASD {
    actor FaceSpeechDatabase {
        var speakers: [UUID: (face: FaceEmbedding, voice: String)] = [:]
        
    }
}
