import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {

  private var splashView: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // White background while Flutter engine loads
    self.backgroundColor = NSColor.white

    // --- Splash screen overlay ---
    addSplashScreen(to: flutterViewController.view)

    // Channel to remove splash when Flutter is ready
    FlutterMethodChannel(
      name: "splash_screen", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { [weak self] (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "remove" {
        self?.removeSplashScreen()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Auto-remove splash after 8s failsafe
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
      self?.removeSplashScreen()
    }

    // Launch at startup channel
    FlutterMethodChannel(
      name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any] {
          LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  private func addSplashScreen(to parentView: NSView) {
    let splash = NSView(frame: parentView.bounds)
    splash.autoresizingMask = [.width, .height]
    splash.wantsLayer = true
    splash.layer?.backgroundColor = NSColor.white.cgColor

    // App icon
    if let appIcon = NSImage(named: "AppIcon") {
      let iconSize: CGFloat = 96
      let iconView = NSImageView(frame: NSRect(
        x: (parentView.bounds.width - iconSize) / 2,
        y: (parentView.bounds.height - iconSize) / 2 + 16,
        width: iconSize, height: iconSize
      ))
      iconView.image = appIcon
      iconView.imageScaling = .scaleProportionallyUpOrDown
      iconView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
      splash.addSubview(iconView)
    }

    // "Roxi" text label
    let label = NSTextField(labelWithString: "Roxi")
    label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
    label.textColor = NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
    label.alignment = .center
    label.sizeToFit()
    label.frame = NSRect(
      x: (parentView.bounds.width - label.frame.width) / 2,
      y: (parentView.bounds.height - 96) / 2 - 24,
      width: label.frame.width, height: label.frame.height
    )
    label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    splash.addSubview(label)

    parentView.addSubview(splash)
    self.splashView = splash
  }

  private func removeSplashScreen() {
    guard let splash = self.splashView else { return }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.3
      splash.animator().alphaValue = 0
    }, completionHandler: {
      splash.removeFromSuperview()
    })
    self.splashView = nil
  }

  // window manager hidden at launch
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
