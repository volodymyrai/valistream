//
//  ValidationSession+Monitoring.swift
//  ValistreamCore
//

import Foundation

extension ValidationSession {

    // MARK: - Live monitoring

    func monitor(
        selected: [PlaylistSelection.Candidate],
        loadedByURL: [URL: LoadedPlaylist],
        kind: StreamKind
    ) async {
        let deadline = config.timeLimit.map { now().addingTimeInterval($0.seconds) }
        await withDiscardingTaskGroup { group in
            for candidate in selected {
                let initial = loadedByURL[candidate.url]
                group.addTask {
                    await self.monitorPlaylist(candidate, initial: initial, kind: kind, deadline: deadline)
                }
            }
        }
    }

    func monitorPlaylist(
        _ candidate: PlaylistSelection.Candidate,
        initial: LoadedPlaylist?,
        kind: StreamKind,
        deadline: Date?
    ) async {
        let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id

        guard var previous = initial?.playlist?.media else {
            setMonitorState(presentationID, .stopped)
            return
        }
        setMonitorState(presentationID, .monitoring)

        var refreshIndex = 0
        var lastChangedAt = now()
        var lastChanged = true
        var targetDuration = duration(previous.targetDuration)

        while stopRequested == false {
            if previous.hasEndList { break }
            if deadlinePassed(deadline) { break }

            let scheduler = RefreshScheduler(targetDuration: targetDuration)
            let delay = refreshIndex == 0 ? scheduler.initialDelay : scheduler.nextDelay(didChange: lastChanged)

            if config.verboseEvents {
                let delaySecs = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
                emit(.trace(.refreshScheduled(playlistID: presentationID, delaySeconds: delaySecs)))
            }

            do {
                try await sleep(delay)
            } catch {
                break
            }
            if stopRequested { break }
            if deadlinePassed(deadline) { break }

            refreshIndex += 1
            let snapshotLabel = SnapshotID.label(id: presentationID, index: refreshIndex)

            if config.verboseEvents {
                emit(.trace(.fetchIntent(snapshotID: snapshotLabel)))
            }

            let fetchStart = now()
            let load = await loader.load(candidate.url, role: candidate.role)

            if config.verboseEvents {
                let durationMs = Int(now().timeIntervalSince(fetchStart) * 1_000)
                let httpStatus = load.result.metadata.httpStatus ?? 0
                let bytes = load.result.body.count
                emit(.trace(.fetchResult(
                    snapshotID: snapshotLabel,
                    httpStatus: httpStatus,
                    durationMs: durationMs,
                    bytes: bytes
                )))
            }

            await archiveFetch(load.result, requestURL: load.url, playlistID: presentationID)

            if config.verboseEvents, load.playlist?.media != nil {
                let olderLabel = SnapshotID.label(id: presentationID, index: refreshIndex - 1)
                emit(.trace(.continuityCompare(
                    olderSnapshotID: olderLabel,
                    newerSnapshotID: snapshotLabel
                )))
            }

            if config.verboseEvents, load.result.outcome == .success {
                let archivePath = "playlists/\(presentationID)/\(snapshotLabel).m3u8"
                emit(.trace(.stored(snapshotID: snapshotLabel, archivePath: archivePath)))
            }

            incrementRefreshCount(presentationID)
            for violation in load.deliveryViolations {
                record(violation, resource: candidate.url, refreshIndex: refreshIndex)
            }
            var changed = false
            let findingsBefore = recordedFindings.count

            if let media = load.playlist?.media {
                evaluateStructural(load: load, kind: kind, refreshIndex: refreshIndex)
                for violation in continuityChecker.check(previous: previous, current: media) {
                    record(violation, resource: candidate.url, refreshIndex: refreshIndex)
                }
                changed = media != previous
                if changed {
                    lastChangedAt = now()
                    targetDuration = duration(media.targetDuration)
                    setMonitorState(presentationID, .monitoring)
                }
                previous = media

                if config.verboseEvents {
                    let newFindings = recordedFindings.count - findingsBefore
                    if newFindings == 0 {
                        emit(.trace(.validationPlaylistOK(snapshotID: snapshotLabel)))
                    } else {
                        let errors = recordedFindings.suffix(newFindings).count { $0.severity == .error }
                        let warnings = recordedFindings.suffix(newFindings).count { $0.severity == .warning }
                        emit(.trace(.validationPlaylistFail(
                            snapshotID: snapshotLabel,
                            errorCount: errors,
                            warnCount: warnings
                        )))
                    }
                }
            }
            lastChanged = changed
            if changed == false {
                evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
            }

            let findingsThisRefresh = recordedFindings.count - findingsBefore
            let errorsThisRefresh = recordedFindings.suffix(findingsThisRefresh).count { $0.severity == .error }
            let warningsThisRefresh = recordedFindings.suffix(findingsThisRefresh).count { $0.severity == .warning }
            emit(.refreshCompleted(
                playlistID: presentationID,
                index: refreshIndex,
                errors: errorsThisRefresh,
                warnings: warningsThisRefresh
            ))

            emit(.activity(ActivityProgress(
                activity: "monitoring live",
                completed: refreshIndex,
                refreshes: refreshIndex,
                aliasInScope: presentationID,
                sessionRefreshTotal: sessionRefreshTotal
            )))

            await writeReport(interruption: nil)
        }

        setMonitorState(presentationID, .stopped)
    }

    /// Reports whether the monitoring deadline has passed, flagging `timeLimitExpired` if so.
    private func deadlinePassed(_ deadline: Date?) -> Bool {
        guard let deadline, now() >= deadline else { return false }
        timeLimitExpired = true
        return true
    }

    // MARK: - Rule evaluation

    func evaluateStructural(load: LoadedPlaylist, kind: StreamKind, refreshIndex: Int) {
        guard let playlist = load.playlist else { return }
        let context = RuleContext(
            playlist: playlist,
            tokens: load.tokens,
            resource: load.url,
            streamKind: kind,
            refreshIndex: refreshIndex
        )
        for violation in engine.evaluate(context) {
            recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
        }
        if let media = playlist.media {
            for violation in classifier.infoViolations(for: media, tokens: load.tokens) {
                recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
            }
        }
    }

    func evaluateStaleness(
        _ candidate: PlaylistSelection.Candidate,
        since lastChangedAt: Date,
        target: Duration,
        refreshIndex: Int
    ) {
        let staleFor = Duration.seconds(now().timeIntervalSince(lastChangedAt))
        guard let violation = stalenessDetector.violation(staleFor: staleFor, targetDuration: target) else {
            return
        }
        record(violation, resource: candidate.url, refreshIndex: refreshIndex)
        // Match the presentation ID used by every other monitoring event (FR-013-ID), not the
        // internal candidate ID.
        let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
        setMonitorState(presentationID, violation.severity == .error ? .staleError : .staleWarning)
    }
}
