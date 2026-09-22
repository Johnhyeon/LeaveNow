import Foundation

/// 설정의 '평일 출근 알림'을 현재 추정치로 다시 계산해 예약한다.
enum RoutineSync {
    struct Plan {
        let train: Train
        let leaveByMinutes: Int
        let platformMinutes: Int
    }

    /// 사용자가 고른 목표 시각 이후 첫 평일 열차 기준으로 출발 시각(분 단위)을 계산
    static func plan(records: [TripRecord]) -> Plan? {
        let d = UserDefaults.standard
        let targetMinutes = d.object(forKey: "routineTargetMinutes") as? Int ?? (8 * 60)
        let direction = Direction.parse(d.string(forKey: "routineDirection"))
        let stationCode = d.string(forKey: "stationCode") ?? TimetableStore.defaultStationCode
        let bufferMinutes = d.object(forKey: "bufferMinutes") as? Int ?? 4
        let mode = EstimateMode(rawValue: d.string(forKey: "estimateMode") ?? "") ?? .safe
        let includePrep = d.object(forKey: "includePrep") as? Bool ?? true

        guard let train = TimetableStore.shared.trains(stationCode: stationCode, direction: direction, dayType: .weekday)
            .first(where: { $0.minutesOfDay >= targetMinutes && $0.minutesOfDay >= 180 }) else { return nil }

        let estimates = Estimator.estimates(records: records, mode: mode)
        let travel = Estimator.travelSeconds(estimates, includePrep: includePrep)
        let platform = train.minutesOfDay - bufferMinutes
        let leaveBy = platform - Int((travel / 60).rounded(.up))
        return Plan(train: train, leaveByMinutes: leaveBy, platformMinutes: platform)
    }

    static func resync(records: [TripRecord]) async {
        let d = UserDefaults.standard
        let enabled = d.bool(forKey: "routineEnabled")
        let lead = d.object(forKey: "leadMinutes") as? Int ?? 5
        let stationCode = d.string(forKey: "stationCode") ?? TimetableStore.defaultStationCode
        await TimetableStore.shared.ensureLoaded(stationCode: stationCode)

        let manager = NotificationManager.shared
        guard enabled, let plan = plan(records: records) else {
            manager.cancelRoutine()
            await manager.refresh()
            return
        }
        await manager.scheduleRoutine(train: plan.train,
                                      leaveByMinutes: plan.leaveByMinutes,
                                      platformMinutes: plan.platformMinutes,
                                      leadMinutes: lead)
    }
}
