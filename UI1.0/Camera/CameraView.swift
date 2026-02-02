//
//  CameraView.swift
//  audi
//
//  Created by Sebastian Zimmerman on 12/17/25.
//

import SwiftUI

struct CameraView: View {
    @StateObject private var camera = CameraModel()
    @State private var currentZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    var body: some View {
        CameraPreview(session: camera.session)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onAppear { camera.requestAndStart() }
            .onDisappear { camera.stop() }
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        _ = camera.setZoomFactor(lastZoom * scale)
                    }
                    .onEnded { scale in
                        lastZoom = camera.setZoomFactor(lastZoom * scale)
                    }
            )
            .onAppear {
                AppDelegate.orientationLock = .landscape
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
            .onDisappear {
                AppDelegate.orientationLock = .portrait
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        
    }
}
