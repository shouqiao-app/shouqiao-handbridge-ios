import Combine
import CoreLocation
import Foundation

/// SOS location flow for iOS.
///
/// iOS CoreLocation does not expose a public "GPS provider" switch. The
/// controller therefore starts with best accuracy (usually GPS), and after
/// 2.5s restarts with hundred-meter accuracy so CoreLocation can use Wi-Fi or
/// cell positioning. The total request is capped at 8 seconds.
final class SosLocationController: NSObject, ObservableObject {
    @Published private(set) var status = "位置：紧急手势时临时获取"
    @Published private(set) var message = ""
    @Published private(set) var isLocating = false

    var onMessage: ((String) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var fallbackWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private var bestLocation: CLLocation?
    private var bestAccuracy: CLLocationAccuracy = .greatestFiniteMagnitude

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start() {
        cancel()
        guard CLLocationManager.locationServicesEnabled() else {
            fail("位置：定位服务不可用，可先发送不带位置的求助。")
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            status = "位置：等待定位授权…"
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            fail("位置：未授权，可先发送不带位置的求助。")
        default:
            beginRequest()
        }
    }

    func cancel() {
        fallbackWork?.cancel()
        timeoutWork?.cancel()
        fallbackWork = nil
        timeoutWork = nil
        manager.stopUpdatingLocation()
        geocoder.cancelGeocode()
        isLocating = false
        bestLocation = nil
        bestAccuracy = .greatestFiniteMagnitude
    }

    func retry() {
        start()
    }

    private func beginRequest() {
        isLocating = true
        bestLocation = nil
        bestAccuracy = .greatestFiniteMagnitude
        status = "位置：正在优先获取 GPS，最多等待 8 秒…"
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()

        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.isLocating else { return }
            guard self.bestLocation == nil else {
                self.status = "位置：已获取坐标，继续等待更精确结果…"
                return
            }
            self.status = "位置：GPS 暂不可用，正在尝试网络定位…"
            self.manager.stopUpdatingLocation()
            self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            self.manager.startUpdatingLocation()
        }
        fallbackWork = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: fallback)

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isLocating else { return }
            if let best = self.bestLocation {
                self.finish(with: best)
            } else {
                self.fail("位置：8 秒内未获取，可先发送不带位置的求助。")
            }
        }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeout)
    }

    private func finish(with location: CLLocation) {
        guard isLocating else { return }
        isLocating = false
        fallbackWork?.cancel()
        timeoutWork?.cancel()
        manager.stopUpdatingLocation()
        status = "位置：已获取坐标，正在解析地址…"

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let address = Self.formatAddress(placemarks?.first)
            DispatchQueue.main.async {
                self.message = Self.buildMessage(
                    location: location,
                    address: address,
                    failure: nil
                )
                self.status = address.isEmpty
                    ? "位置：已获取坐标；地址暂未解析"
                    : "位置：已定位至 \(address)"
                self.onMessage?(self.message)
            }
        }
    }

    private func fail(_ text: String) {
        isLocating = false
        fallbackWork?.cancel()
        timeoutWork?.cancel()
        manager.stopUpdatingLocation()
        status = text
        message = Self.buildMessage(location: nil, address: nil, failure: text)
        onMessage?(message)
        bestLocation = nil
        bestAccuracy = .greatestFiniteMagnitude
    }

    private static func formatAddress(_ placemark: CLPlacemark?) -> String {
        guard let placemark else { return "" }
        let parts = [
            placemark.country,
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ].compactMap { $0 }
        return parts.joined()
    }

    private static func buildMessage(
        location: CLLocation?,
        address: String?,
        failure: String?
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let time = formatter.string(from: Date())

        var lines = [
            "【求助】我可能需要帮助，请尽快联系我。",
            "时间：\(time)"
        ]

        if let location {
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            let place = (address?.isEmpty == false ? address! : "地址暂未解析")
            lines.append(String(format: "位置：%@；坐标 %.6f, %.6f（约 %.0f 米精度）",
                                place, latitude, longitude, location.horizontalAccuracy))
            lines.append("地图：https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
        } else {
            lines.append("位置：\(failure ?? "未能获取（8 秒超时），可先发送求助")")
        }

        lines.append("可见情况：系统观察到双掌张开后双拳保持 5 秒的约定求助序列。")
        lines.append("具体危险类型尚待确认。")
        return lines.joined(separator: "\n")
    }
}

extension SosLocationController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !isLocating {
                beginRequest()
            }
        case .denied, .restricted:
            fail("位置：未授权，可先发送不带位置的求助。")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  abs(location.timestamp.timeIntervalSinceNow) <= 30 else {
                continue
            }
            if location.horizontalAccuracy < bestAccuracy {
                bestAccuracy = location.horizontalAccuracy
                bestLocation = location
            }
        }
        guard let best = bestLocation else { return }
        if best.horizontalAccuracy <= 15 {
            finish(with: best)
        } else {
            status = String(
                format: "位置：已获取坐标，当前约 %.0f 米精度，正在继续优化…",
                best.horizontalAccuracy
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            fail("位置：未授权，可先发送不带位置的求助。")
        }
        // Other errors wait for the overall 8-second timeout; a transient
        // failure should not discard a later valid update.
    }
}
