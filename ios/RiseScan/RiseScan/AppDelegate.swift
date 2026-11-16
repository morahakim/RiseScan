//
//  AppDelegate.swift
//  RiseScan
//
//  Created by mora hakim on 16/11/26.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundUploadService.shared
            .setBackgroundCompletionHandler(completionHandler)
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundUploadService.shared.restoreBackgroundSession()
        return true
    }
}
