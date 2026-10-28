import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Folder whose security-scoped access is currently open.
  private var scopedURL: URL?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Dock badge with the download progress ("3/23").
    let dock = FlutterMethodChannel(
      name: "dock_badge", binaryMessenger: flutterViewController.engine.binaryMessenger)
    dock.setMethodCallHandler { call, result in
      if call.method == "setBadge" {
        NSApp.dockTile.badgeLabel = (call.arguments as? String).flatMap { $0.isEmpty ? nil : $0 }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Remembers the folder picked by the user across launches (sandbox).
    let folder = FlutterMethodChannel(
      name: "folder_access", binaryMessenger: flutterViewController.engine.binaryMessenger)
    folder.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "saveBookmark":
        guard let path = call.arguments as? String else { return result(false) }
        let url = URL(fileURLWithPath: path)
        do {
          let data = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
          UserDefaults.standard.set(data, forKey: "folderBookmark")
          self?.scopedURL?.stopAccessingSecurityScopedResource()
          self?.scopedURL = url
          result(true)
        } catch {
          result(FlutterError(code: "BOOKMARK", message: error.localizedDescription, details: nil))
        }
      case "restoreBookmark":
        guard let data = UserDefaults.standard.data(forKey: "folderBookmark") else {
          return result(nil)
        }
        var stale = false
        guard
          let url = try? URL(
            resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
            bookmarkDataIsStale: &stale),
          url.startAccessingSecurityScopedResource()
        else { return result(nil) }
        self?.scopedURL?.stopAccessingSecurityScopedResource()
        self?.scopedURL = url
        result(url.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
