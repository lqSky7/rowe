import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Pure, testable behavioral learning & nudge decision engine for Rowe.
/// Zero blocking — observes habits, deduplicates Mac + iOS intervals via 1D sweep-line union,
/// learns Beta-EWMA receptivity per (target, dayType, 2h slot), and picks quick (<= 25m) unlocked tasks.
public struct FocusNudgeEngine: Sendable {
    public static let maxQuickTaskMinutes = 25
    public static let microBreakGapSeconds: TimeInterval = 5 * 60
    public static let globalCooldownSeconds: TimeInterval = 45 * 60
    public static let perTargetCooldownSeconds: TimeInterval = 120 * 60
    public static let dailyNudgeCap = 4
    public static let autoSilenceThreshold = 0.20
    public static let autoProbeIntervalSeconds: TimeInterval = 21 * 86400 // ~3 weeks
    public static let recencyHalfLifeDays: Double = 21.0
    public static let minPersonalizedMedianMinutes: Double = 20.0

    public init() {}

    // MARK: - 1. Cross-Device 1D Sweep-Line Interval Union & Micro-Break Stitching

    /// Merges overlapping intervals across Mac & iOS for a target (neutralizing double-counting)
    /// and stitches consecutive sessions separated by <= 5 minutes while preserving initiation slot.
    public func mergedSessions(for target: String, from intervals: [UsageInterval]) -> [UsageInterval] {
        let filtered = intervals
            .filter { $0.canonicalTarget == target && $0.durationSeconds >= 5 }
            .sorted { $0.startUTC < $1.startUTC }
        guard !filtered.isEmpty else { return [] }

        // Step 1: If macOS foreground overlaps an iOS DeviceActivity bucket, prefer macOS fidelity.
        var merged: [UsageInterval] = []
        for interval in filtered {
            guard var last = merged.last else {
                merged.append(interval)
                continue
            }
            let gap = interval.startUTC.timeIntervalSince(last.endUTC)
            if gap <= Self.microBreakGapSeconds {
                // Overlapping or within 5-minute micro-break: union them, preserving initiation startUTC & tzOffset
                let newEnd = max(last.endUTC, interval.endUTC)
                let cappedEnd = min(newEnd, last.startUTC.addingTimeInterval(4 * 3600))
                last.endUTC = cappedEnd
                if interval.sourceFidelity == .macForeground {
                    last.sourceFidelity = .macForeground
                }
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    // MARK: - 2. Recency-Weighted Median Scroll Baseline (21-Day Half-Life)

    /// Returns `(sampleCountInSlot, totalTargetSessions, weightedMedianMinutes)` using initiation-slot attribution.
    public func slotBaseline(
        for slotKey: FocusSlotKey,
        in state: FocusBehaviorState,
        now: Date = Date()
    ) -> (slotSamples: Int, totalTargetSamples: Int, medianMinutes: Double?) {
        let sessions = mergedSessions(for: slotKey.canonicalTarget, from: state.intervals)
        let matching = sessions.filter { s in
            FocusSlotKey.from(date: s.startUTC, tzOffsetMinutes: s.tzOffsetMinutes, target: s.canonicalTarget) == slotKey
        }
        let samples = matching.isEmpty ? sessions : matching
        guard !samples.isEmpty else { return (0, 0, nil) }

        let weighted: [(minutes: Double, weight: Double)] = samples.map { s in
            let ageDays = max(0, now.timeIntervalSince(s.startUTC) / 86400.0)
            let w = pow(0.5, ageDays / Self.recencyHalfLifeDays)
            return (s.durationMinutes, w)
        }.sorted { $0.minutes < $1.minutes }

        let totalW = weighted.reduce(0.0) { $0 + $1.weight }
        guard totalW > 0 else { return (matching.count, sessions.count, nil) }

        var cumulative = 0.0
        for item in weighted {
            cumulative += item.weight
            if cumulative >= totalW * 0.5 {
                return (matching.count, sessions.count, item.minutes)
            }
        }
        return (matching.count, sessions.count, weighted.last?.minutes)
    }

    /// Computes total deduplicated minutes per 2-hour circadian slot (0...11) across all tracked targets
    /// using wall-clock boundary splitting (for calm analytics charts).
    public func circadianMinutesBySlot(
        in state: FocusBehaviorState,
        daysBack: Int = 7,
        now: Date = Date()
    ) -> [Double] {
        var buckets = Array(repeating: 0.0, count: 12)
        let cutoff = now.addingTimeInterval(-Double(daysBack) * 86400)
        let targets = Set(state.intervals.map(\.canonicalTarget))

        for target in targets {
            let sessions = mergedSessions(for: target, from: state.intervals).filter { $0.endUTC >= cutoff }
            for session in sessions {
                var cursor = max(session.startUTC, cutoff)
                let end = session.endUTC
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: session.tzOffsetMinutes * 60) ?? .current

                while cursor < end {
                    let comps = cal.dateComponents([.year, .month, .day, .hour], from: cursor)
                    let slot = (comps.hour ?? 0) / 2
                    let nextSlotStartHour = (slot + 1) * 2
                    var nextComps = DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: nextSlotStartHour, minute: 0, second: 0)
                    if nextSlotStartHour >= 24 {
                        nextComps.hour = 0
                        if let nextDay = cal.date(byAdding: .day, value: 1, to: cursor) {
                            let nd = cal.dateComponents([.year, .month, .day], from: nextDay)
                            nextComps.year = nd.year
                            nextComps.month = nd.month
                            nextComps.day = nd.day
                        }
                    }
                    let boundary = cal.date(from: nextComps) ?? end
                    let sliceEnd = min(end, boundary)
                    if sliceEnd <= cursor { break }
                    buckets[min(11, max(0, slot))] += sliceEnd.timeIntervalSince(cursor) / 60.0
                    cursor = sliceEnd
                }
            }
        }
        return buckets
    }

    // MARK: - 3. Nudge Decision (Zero Blocking, Cold Start, Cooldowns, Receptivity, Quick Tasks Only)

    public func evaluateNudge(
        target: String,
        candidates: [NudgeCandidateTask],
        state: FocusBehaviorState,
        now: Date = Date(),
        tzOffsetMinutes: Int = TimeZone.current.secondsFromGMT() / 60,
        bypassColdStartForPreview: Bool = false
    ) -> FocusSuggestion? {
        guard state.isEnabled else { return nil }

        // User choice: stay completely silent when no quick (<= 25m) pending tasks exist.
        guard let picked = selectBestQuickTask(from: candidates, state: state, now: now) else {
            return nil
        }

        let slotKey = FocusSlotKey.from(date: now, tzOffsetMinutes: tzOffsetMinutes, target: target)
        let baseline = slotBaseline(for: slotKey, in: state, now: now)

        if !bypassColdStartForPreview {
            // Daily cap & consecutive-dismiss circuit breaker
            let todayKey = Self.dayKey(for: now, tzOffsetMinutes: tzOffsetMinutes)
            if state.lastNudgeDayKey == todayKey {
                if state.dailyNudgeCount >= Self.dailyNudgeCap { return nil }
                if state.consecutiveDismissesToday >= 3 { return nil }
            }

            // Global cooldown across all apps & synced devices
            if let globalUntil = state.globalCooldownUntilUTC, now < globalUntil {
                return nil
            }

            // Per-target cross-device lease cooldown
            if let lease = state.leases.first(where: { $0.canonicalTarget == target }), now < lease.cooldownUntilUTC {
                return nil
            }

            // Phase 0 Cold Start: observe silently until at least 3 total sessions exist for this target
            if baseline.totalTargetSamples < 3 {
                return nil
            }

            // Never nudge on targets whose typical session is under 15 minutes
            if let med = baseline.medianMinutes, med < 15.0 {
                return nil
            }
        }

        // Receptivity check + 3-week gentle auto-probe for auto-silenced slots
        var isAutoProbe = false
        if !bypassColdStartForPreview, let rec = state.receptivityBySlot[slotKey.storageKey], rec.isAutoSilenced {
            let lastCheck = rec.lastProbeUTC ?? rec.lastSilencedUTC ?? rec.lastUpdatedUTC
            let eligibleForProbe = now.timeIntervalSince(lastCheck) >= Self.autoProbeIntervalSeconds
                && (baseline.medianMinutes ?? 0) >= 45.0
            if eligibleForProbe {
                isAutoProbe = true
            } else {
                return nil
            }
        }

        let isPersonalized = (baseline.slotSamples >= 3 && (baseline.medianMinutes ?? 0) >= Self.minPersonalizedMedianMinutes)
            || bypassColdStartForPreview
        let predictedMins = baseline.medianMinutes.map { max(15, Int(($0 / 5.0).rounded() * 5)) }
        let appName = CanonicalTargetRegistry.displayName(for: target)
        let iconName = CanonicalTargetRegistry.iconName(for: target)

        let (headline, detail) = buildCalmCopy(
            appName: appName,
            taskTitle: picked.task.title,
            estimatedMinutes: picked.estimatedMinutes,
            predictedScrollMinutes: isPersonalized ? (predictedMins ?? 60) : nil,
            now: now,
            tzOffsetMinutes: tzOffsetMinutes
        )

        return FocusSuggestion(
            canonicalTarget: target,
            displayAppName: appName,
            iconName: iconName,
            headline: headline,
            detailLine: detail,
            task: picked.task,
            estimatedMinutes: picked.estimatedMinutes,
            predictedScrollMinutes: isPersonalized ? predictedMins : nil,
            slotKey: slotKey,
            isPersonalized: isPersonalized,
            isAutoProbe: isAutoProbe
        )
    }

    // MARK: - 4. Task Selection & Heuristic Duration Estimation

    public func estimateMinutesDeterministic(for title: String) -> Int {
        let lower = title.lowercased()
        // Explicit duration hint like "10m", "20 min", "1h", "2 hours"
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*(min|mins|minute|minutes|m)\b"#),
           let m = regex.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)),
           let mins = Int((lower as NSString).substring(with: m.range(at: 1))) {
            return max(3, min(180, mins))
        }
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})\s*(hr|hrs|hour|hours|h)\b"#),
           let m = regex.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)),
           let hrs = Int((lower as NSString).substring(with: m.range(at: 1))) {
            return max(30, min(240, hrs * 60))
        }

        // Quick-win verbs
        let quickKeywords = ["reply", "email", "mail", "call", "text", "dm", "book", "pay", "submit", "upload", "send", "check", "order", "ping", "buy", "schedule", "confirm", "update", "fix"]
        if quickKeywords.contains(where: { lower.contains($0) }) {
            return 10
        }

        // Medium-quick study/review tasks
        let reviewKeywords = ["review", "read", "notes", "outline", "quiz", "flashcards", "summary", "clean", "organize", "prep"]
        if reviewKeywords.contains(where: { lower.contains($0) }) {
            return 15
        }

        // Heavy deep-work epics (> 25m -> filtered out per user choice to stay silent on long-only lists)
        let heavyKeywords = ["build full", "rewrite", "refactor entire", "thesis", "dissertation", "research paper", "complete project", "full exam"]
        if heavyKeywords.contains(where: { lower.contains($0) }) {
            return 60
        }

        return 15
    }

    private func selectBestQuickTask(
        from candidates: [NudgeCandidateTask],
        state: FocusBehaviorState,
        now: Date
    ) -> (task: NudgeCandidateTask, estimatedMinutes: Int)? {
        let cal = Calendar.current
        var scored: [(task: NudgeCandidateTask, est: Int, priority: Double)] = []

        for task in candidates {
            let stat = state.taskStats[task.id]
            // If user edited a previously excluded task, re-enable it automatically
            let editedSinceExclude = (stat?.lastEditedAt != nil && task.updatedAt > stat!.lastEditedAt!)
            if let stat, stat.isExcluded && !editedSinceExclude { continue }
            if let until = stat?.cooldownUntilUTC, now < until && !editedSinceExclude { continue }

            let est = stat?.estimatedMinutes ?? estimateMinutesDeterministic(for: task.title)
            guard est <= Self.maxQuickTaskMinutes else { continue }

            var prio = 50.0
            if let sched = task.scheduleDate {
                if cal.isDateInToday(sched) { prio += 35 }
                else if sched < now { prio += 40 } // Overdue quick win
                else if cal.isDateInTomorrow(sched) { prio += 15 }
            }
            if let deadline = task.deadlineDate {
                let hoursLeft = deadline.timeIntervalSince(now) / 3600.0
                if hoursLeft <= 24 { prio += 30 }
                else if hoursLeft <= 72 { prio += 15 }
            }
            // Prefer crisp 5-15m micro-wins
            if est <= 15 { prio += 12 }
            prio -= Double(stat?.dismissCount ?? 0) * 18.0
            scored.append((task, est, prio))
        }

        guard let best = scored.max(by: { $0.priority < $1.priority }) else { return nil }
        return (best.task, best.est)
    }

    // MARK: - 5. Beta-EWMA Receptivity & Cooldown Updates

    public func recordOutcome(
        _ outcome: NudgeOutcome,
        for suggestion: FocusSuggestion,
        deviceId: String,
        into state: inout FocusBehaviorState,
        now: Date = Date(),
        tzOffsetMinutes: Int = TimeZone.current.secondsFromGMT() / 60
    ) {
        let todayKey = Self.dayKey(for: now, tzOffsetMinutes: tzOffsetMinutes)
        if state.lastNudgeDayKey != todayKey {
            state.lastNudgeDayKey = todayKey
            state.dailyNudgeCount = 0
            state.consecutiveDismissesToday = 0
        }
        state.dailyNudgeCount += 1

        // Update Beta-EWMA receptivity (gamma = 0.85)
        let key = suggestion.slotKey.storageKey
        var rec = state.receptivityBySlot[key] ?? SlotReceptivity(lastUpdatedUTC: now)
        let gamma = 0.85
        rec.alpha = max(0.25, rec.alpha * gamma)
        rec.beta = max(0.25, rec.beta * gamma)

        switch outcome {
        case .accepted:
            rec.alpha += 1.0
            rec.acceptedCount += 1
            rec.lastSilencedUTC = nil
            state.consecutiveDismissesToday = 0
            let quiet = TimeInterval(suggestion.estimatedMinutes + 30) * 60
            state.globalCooldownUntilUTC = now.addingTimeInterval(quiet)
        case .dismissed:
            rec.beta += 1.0
            rec.dismissedCount += 1
            state.consecutiveDismissesToday += 1
            let multiplier = state.consecutiveDismissesToday >= 2 ? 2.0 : 1.0
            state.globalCooldownUntilUTC = now.addingTimeInterval(Self.globalCooldownSeconds * multiplier)
            // Per-task backoff: 1st -> 24h, 2nd -> 7d, 3rd -> exclude until edited
            var tStat = state.taskStats[suggestion.task.id] ?? TaskNudgeStats(
                taskId: suggestion.task.id,
                estimatedMinutes: suggestion.estimatedMinutes,
                lastEditedAt: suggestion.task.updatedAt
            )
            tStat.dismissCount += 1
            tStat.lastEditedAt = suggestion.task.updatedAt
            if tStat.dismissCount == 1 {
                tStat.cooldownUntilUTC = now.addingTimeInterval(24 * 3600)
            } else if tStat.dismissCount == 2 {
                tStat.cooldownUntilUTC = now.addingTimeInterval(7 * 86400)
            } else {
                tStat.isExcluded = true
            }
            state.taskStats[suggestion.task.id] = tStat
        case .ignored:
            rec.beta += 0.5
            state.globalCooldownUntilUTC = now.addingTimeInterval(Self.globalCooldownSeconds)
        case .markedProductive:
            // Don't penalize receptivity harshly; just back off for this target for 2 hours
            state.globalCooldownUntilUTC = now.addingTimeInterval(30 * 60)
        }

        rec.lastUpdatedUTC = now
        rec.lastNudgedUTC = now
        if suggestion.isAutoProbe {
            rec.lastProbeUTC = now
        }
        if rec.isAutoSilenced && rec.lastSilencedUTC == nil {
            rec.lastSilencedUTC = now
        }
        state.receptivityBySlot[key] = rec

        // Record cross-device lease
        let lease = NudgeLease(
            canonicalTarget: suggestion.canonicalTarget,
            slotKey: key,
            issuedAtUTC: now,
            cooldownUntilUTC: now.addingTimeInterval(Self.perTargetCooldownSeconds),
            deviceId: deviceId
        )
        state.leases.removeAll { $0.canonicalTarget == suggestion.canonicalTarget }
        state.leases.append(lease)
        state.updatedAt = now
    }

    // MARK: - 6. Calm Copy Builder

    private func buildCalmCopy(
        appName: String,
        taskTitle: String,
        estimatedMinutes: Int,
        predictedScrollMinutes: Int?,
        now: Date,
        tzOffsetMinutes: Int
    ) -> (headline: String, detail: String) {
        if let mins = predictedScrollMinutes {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: tzOffsetMinutes * 60) ?? .current
            let weekdayName = cal.weekdaySymbols[max(0, min(6, (cal.component(.weekday, from: now)) - 1))]
            let hour = cal.component(.hour, from: now)
            let hourLabel = hour == 0 ? "12 AM" : (hour == 12 ? "12 PM" : (hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"))
            let durStr = mins >= 60
                ? (mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h \(mins % 60)m")
                : "\(mins)m"
            let headline = "Usually \(weekdayName) around \(hourLabel) on \(appName) runs ~\(durStr)"
            let detail = "Knock out \"\(taskTitle)\" (~\(estimatedMinutes)m) first, then scroll freely?"
            return (headline, detail)
        } else {
            let headline = "Quick \(estimatedMinutes)m win before \(appName)?"
            let detail = "Knock out \"\(taskTitle)\" first, then scroll freely."
            return (headline, detail)
        }
    }

    public static func dayKey(for date: Date, tzOffsetMinutes: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: tzOffsetMinutes * 60) ?? .current
        return f.string(from: date)
    }
}

// MARK: - On-Device Apple Intelligence Task Estimator (FoundationModels + Deterministic Fallback)

public actor FocusIntelligenceEstimator {
    private let fallbackEngine = FocusNudgeEngine()

    public init() {}

    /// Estimates task duration in minutes completely on-device using Apple Intelligence (`FoundationModels`)
    /// on macOS 26 / iOS 26 when available, falling back cleanly to deterministic heuristics otherwise.
    /// Zero-knowledge safe: only accepts `NudgeCandidateTask` (unlocked tasks only).
    public func estimateMinutes(for task: NudgeCandidateTask) async -> Int {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            if let aiEstimate = await estimateWithAppleIntelligence(title: task.title) {
                return max(3, min(180, aiEstimate))
            }
        }
        #endif
        return fallbackEngine.estimateMinutesDeterministic(for: task.title)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func estimateWithAppleIntelligence(title: String) async -> Int? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        do {
            let session = LanguageModelSession(
                instructions: "Estimate how many minutes a single person needs to complete the given short todo task. Reply with ONLY an integer number of minutes between 5 and 120."
            )
            let response = try await session.respond(to: "Task: \(title)")
            let digits = response.content.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits)
        } catch {
            return nil
        }
    }
    #endif
}
