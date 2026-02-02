//
//  OrientationManager.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/2/26.
//



import SwiftUI

class landscapeUIViewController<Content: View>: UIHostingController<Content> {
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }
    override var shouldAutorotate: Bool {
        true
    }
    
}

struct LandscapeView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    
    func makeUIViewController(context: Context) -> UIViewController {
        landscapeUIViewController(rootView: content)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
