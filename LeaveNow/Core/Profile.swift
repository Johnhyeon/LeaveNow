import CoreLocation
import Foundation
import Observation

/// 한 사람의 기본 설정. 첫 설정에서 채우고 설정 화면에서 고친다.
@Observable
final class Profile {
    static let shared = Profile()
    private let d = UserDefaults.standard

    var onboarded: Bool { didSet { d.set(onboarded, forKey: "v2.onboarded") } }
    var homeLat: Double { didSet { d.set(homeLat, forKey: "v2.homeLat") } }
    var homeLon: Double { didSet { d.set(homeLon, forKey: "v2.homeLon") } }
    var homeStation: String { didSet { d.set(homeStation, forKey: "v2.homeStation") } }
    /// 집 현관에서 승강장까지 (분)
    var homeToPlatform: Int { didSet { d.set(homeToPlatform, forKey: "v2.homeToPlatform") } }
    /// 열차 시각보다 이만큼 먼저 승강장에 (분)
    var platformBuffer: Int { didSet { d.set(platformBuffer, forKey: "v2.platformBuffer") } }
    /// 목적지에 이만큼 일찍 도착 (분)
    var arriveEarly: Int { didSet { d.set(arriveEarly, forKey: "v2.arriveEarly") } }
    /// 미리 알림: 나갈 시각 몇 분 전 (분)
    var leadMinutes: Int { didSet { d.set(leadMinutes, forKey: "v2.leadMinutes") } }

    private init() {
        onboarded = d.bool(forKey: "v2.onboarded")
        homeLat = d.double(forKey: "v2.homeLat")
        homeLon = d.double(forKey: "v2.homeLon")
        homeStation = d.string(forKey: "v2.homeStation") ?? ""
        homeToPlatform = d.object(forKey: "v2.homeToPlatform") as? Int ?? 10
        platformBuffer = d.object(forKey: "v2.platformBuffer") as? Int ?? 4
        arriveEarly = d.object(forKey: "v2.arriveEarly") as? Int ?? 10
        leadMinutes = d.object(forKey: "v2.leadMinutes") as? Int ?? 10
    }

    var home: CLLocation? {
        guard homeLat != 0 || homeLon != 0 else { return nil }
        return CLLocation(latitude: homeLat, longitude: homeLon)
    }

    var homeOrigin: OriginInfo {
        OriginInfo(label: "집", station: homeStation, toPlatformMinutes: homeToPlatform)
    }
}
