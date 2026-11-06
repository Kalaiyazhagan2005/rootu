import Flutter
import UIKit
import CoreLocation
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate, FlutterStreamHandler {
  private let methodChannelName = "com.example.rootu_mobile/gps_hardware"
  private let eventChannelName = "com.example.rootu_mobile/gps_stream"

  private var locationManager: CLLocationManager?
  private var eventSink: FlutterEventSink?
  private var feedbackGenerator: UIImpactFeedbackGenerator?
  private var latestHeading: Double = -1.0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let binaryMessenger = engineBridge.pluginRegistry.binaryMessenger
    setupPlatformChannels(messenger: binaryMessenger)
  }

  private func setupPlatformChannels(messenger: FlutterBinaryMessenger) {
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager?.distanceFilter = kCLDistanceFilterNone
    locationManager?.activityType = .automotiveNavigation
    locationManager?.pausesLocationUpdatesAutomatically = false
    locationManager?.headingFilter = 1.0
    locationManager?.headingOrientation = .portrait

    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "getRawGpsLocation":
        if let loc = self.locationManager?.location {
          result(self.locationToMap(location: loc))
        } else {
          result(nil)
        }
      case "startAlarmTone":
        self.startAlarm()
        result(true)
      case "stopAlarmTone":
        self.stopAlarm()
        result(true)
      case "startGpsStream":
        self.locationManager?.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
          self.locationManager?.startUpdatingHeading()
        }
        result(true)
      case "stopGpsStream":
        self.locationManager?.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
          self.locationManager?.stopUpdatingHeading()
        }
        result(true)
      case "isGpsHardwareAvailable":
        result(CLLocationManager.locationServicesEnabled())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)
  }

  // MARK: - FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    locationManager?.requestWhenInUseAuthorization()
    locationManager?.startUpdatingLocation()
    if CLLocationManager.headingAvailable() {
      locationManager?.headingFilter = 1.0
      locationManager?.startUpdatingHeading()
    }
    if let last = locationManager?.location {
      events(locationToMap(location: last))
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager?.stopUpdatingLocation()
    if CLLocationManager.headingAvailable() {
      locationManager?.stopUpdatingHeading()
    }
    self.eventSink = nil
    return nil
  }

  // MARK: - CLLocationManagerDelegate
  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    eventSink?(locationToMap(location: location))
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    if heading >= 0 {
      latestHeading = heading
    }
    if let location = manager.location {
      eventSink?(locationToMap(location: location))
    }
  }

  public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    return false
  }

  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    eventSink?(FlutterError(code: "GPS_ERROR", message: error.localizedDescription, details: nil))
  }

  private func locationToMap(location: CLLocation) -> [String: Any] {
    let speedMps = location.speed > 0 ? location.speed : 0.0
    let bearing = location.course >= 0 ? location.course : 0.0
    let timeMs = Int64(location.timestamp.timeIntervalSince1970 * 1000)
    var isMock = false
    if #available(iOS 15.0, *) {
      isMock = location.sourceInformation?.isSimulatedBySoftware ?? false
    }

    return [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "altitude": location.altitude,
      "speed": speedMps,
      "bearing": bearing,
      "compassHeading": latestHeading,
      "time": timeMs,
      "isMock": isMock
    ]
  }

  // MARK: - Alarm & Haptics
  private func startAlarm() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}

    AudioServicesPlayAlertSound(1005)
    feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
    feedbackGenerator?.prepare()
    feedbackGenerator?.impactOccurred()
  }

  private func stopAlarm() {
    try? AVAudioSession.sharedInstance().setActive(false)
    feedbackGenerator = nil
  }
}
