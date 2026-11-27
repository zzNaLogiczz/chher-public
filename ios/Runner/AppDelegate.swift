import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "chh/update", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "openAppSettings" {
          guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
          }
          UIApplication.shared.open(url, options: [:]) { result($0) }
          return
        }
        guard call.method == "appInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          let files = FileManager.default
          let support = try files.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
          )
          let caches = try files.url(
            for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
          )
          result(["filesDir": support.path, "cacheDir": caches.path])
        } catch {
          result(FlutterError(code: "app_paths", message: nil, details: nil))
        }
      }

    FlutterMethodChannel(name: "chh/image", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "save" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let self = self,
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let image = UIImage(contentsOfFile: path)
        else {
          result(false)
          return
        }

        let context = Unmanaged.passRetained(PhotoSaveResult(result)).toOpaque()
        UIImageWriteToSavedPhotosAlbum(
          image, self, #selector(self.photo(_:didFinishSavingWithError:contextInfo:)), context
        )
      }
  }

  @objc private func photo(
    _ image: UIImage, didFinishSavingWithError error: Error?,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    guard let contextInfo = contextInfo else { return }
    let pending = Unmanaged<PhotoSaveResult>.fromOpaque(contextInfo).takeRetainedValue()
    pending.reply(error == nil)
  }
}

private final class PhotoSaveResult {
  let reply: FlutterResult

  init(_ reply: @escaping FlutterResult) {
    self.reply = reply
  }
}
