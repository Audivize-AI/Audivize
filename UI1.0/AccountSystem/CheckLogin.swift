//
//  LoginView.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/12/26.
//


import SwiftUI
import UIKit

enum loginSwitch: Int{
    case on
        
    case off
}

public class loginClass {
    func checkLogin() -> Bool {
        return UserDefaults.standard.bool(forKey: "isLoggedIn")
    }
    func setLogin(isLoggedIn: Bool) {
        if isLoggedIn == false {
            UserDefaults.standard.set(true, forKey: "isLoggedIn")
        }
    }
}
