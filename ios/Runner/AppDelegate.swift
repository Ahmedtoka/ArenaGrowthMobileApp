import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        GeneratedPluginRegistrant.register(with: self)

        application.registerForRemoteNotifications()

        print("🚀 [APNs] registerForRemoteNotifications called")

        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {

        let token = deviceToken.map {
            String(format: "%02.2hhx", $0)
        }.joined()

        print("✅ [APNs] TOKEN: \(token)")

        super.application(
            application,
            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {

        print("❌ [APNs] REGISTRATION FAILED:")
        print(error.localizedDescription)
        print(error)

        super.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
    }
}