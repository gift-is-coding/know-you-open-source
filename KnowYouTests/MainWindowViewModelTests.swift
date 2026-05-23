import XCTest
@testable import KnowYou

private struct ThrowingSummarizer: SummaryGenerating {
    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        throw URLError(.cannotConnectToHost)
    }
}

private struct StaticSummarizer: SummaryGenerating {
    let response: String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        response
    }
}

private struct HandlerSummarizer: SummaryGenerating {
    let handler: @Sendable (String, String, SummaryInvocationContext) async throws -> String

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        try await handler(dayKey, markdown, context)
    }
}

private actor PlainSummarizerRecorder {
    private var callCount = 0
    private var lastDayKey: String?
    private var lastMarkdown: String?
    private var lastContext: SummaryInvocationContext?

    func record(dayKey: String, markdown: String, context: SummaryInvocationContext) {
        callCount += 1
        lastDayKey = dayKey
        lastMarkdown = markdown
        lastContext = context
    }

    func snapshot() -> (callCount: Int, dayKey: String?, markdown: String?, context: SummaryInvocationContext?) {
        (callCount, lastDayKey, lastMarkdown, lastContext)
    }
}

private final class RecordingPlainSummarizer: SummaryGenerating, @unchecked Sendable {
    let response: String
    let recorder = PlainSummarizerRecorder()

    init(response: String) {
        self.response = response
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        await recorder.record(dayKey: dayKey, markdown: markdown, context: context)
        return response
    }
}

private final class HandlerIncrementalSummarizer: IncrementalSummaryGenerating, @unchecked Sendable {
    let summarizeHandler: @Sendable (String, String, SummaryInvocationContext) async throws -> String
    let summarizeIncrementalHandler: @Sendable (String, String, SummaryInvocationContext) async throws -> String

    init(
        summarizeHandler: @escaping @Sendable (String, String, SummaryInvocationContext) async throws -> String,
        summarizeIncrementalHandler: @escaping @Sendable (String, String, SummaryInvocationContext) async throws -> String
    ) {
        self.summarizeHandler = summarizeHandler
        self.summarizeIncrementalHandler = summarizeIncrementalHandler
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        try await summarizeHandler(dayKey, markdown, context)
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        try await summarizeIncrementalHandler(dayKey, markdown, context)
    }
}

private actor IncrementalSummarizerInvocationRecorder {
    private var summarizeCallCount = 0
    private var summarizeIncrementalCallCount = 0

    func recordSummarize() {
        summarizeCallCount += 1
    }

    func recordSummarizeIncremental() {
        summarizeIncrementalCallCount += 1
    }

    func counts() -> (summarize: Int, summarizeIncremental: Int) {
        (summarizeCallCount, summarizeIncrementalCallCount)
    }
}

private final class RecordingIncrementalSummarizer: SummaryGenerating, IncrementalSummaryGenerating, @unchecked Sendable {
    let summarizeResponse: String
    let summarizeIncrementalResponse: String
    let recorder = IncrementalSummarizerInvocationRecorder()

    init(summarizeResponse: String, summarizeIncrementalResponse: String) {
        self.summarizeResponse = summarizeResponse
        self.summarizeIncrementalResponse = summarizeIncrementalResponse
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        await recorder.recordSummarize()
        return summarizeResponse
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        await recorder.recordSummarizeIncremental()
        return summarizeIncrementalResponse
    }
}

private struct OnboardingBootstrapChunkInvocation: Equatable {
    enum Kind: String, Equatable {
        case fullRecovery
        case incrementalAppend
    }

    var dayKey: String
    var kind: Kind
    var eventIDs: [UUID]
}

private actor OnboardingBootstrapChunkRecorder {
    private var invocations: [OnboardingBootstrapChunkInvocation] = []
    private var incrementalChunkCounts: [String: Int] = [:]

    func record(dayKey: String, kind: OnboardingBootstrapChunkInvocation.Kind, eventIDs: [UUID]) -> Int {
        invocations.append(
            OnboardingBootstrapChunkInvocation(
                dayKey: dayKey,
                kind: kind,
                eventIDs: eventIDs
            )
        )
        guard kind == .incrementalAppend else {
            return 0
        }

        let nextCount = incrementalChunkCounts[dayKey, default: 0] + 1
        incrementalChunkCounts[dayKey] = nextCount
        return nextCount
    }

    func snapshot() -> [OnboardingBootstrapChunkInvocation] {
        invocations
    }
}

private final class RecordingOnboardingBootstrapSummarizer: IncrementalSummaryGenerating, @unchecked Sendable {
    let recorder = OnboardingBootstrapChunkRecorder()
    var failingIncrementalChunkByDay: [String: Int] = [:]

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        let eventIDs = Self.extractEventIDs(from: markdown)
        _ = await recorder.record(dayKey: dayKey, kind: .fullRecovery, eventIDs: eventIDs)
        return Self.fullRecoveryResponse(dayKey: dayKey, eventIDs: eventIDs)
    }

    func summarizeIncremental(
        dayKey: String,
        markdown: String,
        context: SummaryInvocationContext
    ) async throws -> String {
        let eventIDs = Self.extractIncrementalEventIDs(from: markdown)
        let chunkNumber = await recorder.record(dayKey: dayKey, kind: .incrementalAppend, eventIDs: eventIDs)
        if failingIncrementalChunkByDay[dayKey] == chunkNumber {
            throw URLError(.timedOut)
        }
        return Self.incrementalResponse(dayKey: dayKey, eventIDs: eventIDs, chunkNumber: chunkNumber)
    }

    private static func extractEventIDs(from markdown: String) -> [UUID] {
        extractUUIDs(from: markdown)
    }

    private static func extractIncrementalEventIDs(from markdown: String) -> [UUID] {
        guard let range = markdown.range(of: "New events to append from:\n") else {
            return extractUUIDs(from: markdown)
        }
        return extractUUIDs(from: String(markdown[range.upperBound...]))
    }

    private static func extractUUIDs(from text: String) -> [UUID] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var orderedIDs: [UUID] = []
        var seen: Set<UUID> = []
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text),
                  let uuid = UUID(uuidString: String(text[matchRange])),
                  seen.insert(uuid).inserted else {
                continue
            }
            orderedIDs.append(uuid)
        }
        return orderedIDs
    }

    private static func fullRecoveryResponse(dayKey: String, eventIDs: [UUID]) -> String {
        let idList = eventIDs.map(\.uuidString)
        return """
        {
          "sections": [{
            "id": "daily-journal",
            "paragraphs": [
              { "text": "# You did a good job today\\n\\nClosed \(eventIDs.count) onboarding event(s).", "sourceEventIDs": \(jsonArray(idList)) },
              { "text": "# Summary\\n- Bootstrapped \(dayKey) from the first chunk", "sourceEventIDs": \(jsonArray(idList)) },
              { "text": "# Details\\n\\n## Chunk 1\\n\\nProcessed \(eventIDs.count) event(s).", "sourceEventIDs": \(jsonArray(idList)) },
              { "text": "# To-do\\n- [ ] Check the next chunk", "sourceEventIDs": \(jsonArray(idList)) }
            ]
          }]
        }
        """
    }

    private static func incrementalResponse(dayKey: String, eventIDs: [UUID], chunkNumber: Int) -> String {
        let idList = eventIDs.map(\.uuidString)
        return """
        {
          "encouragementToReplace": { "text": "Closed chunk \(chunkNumber + 1) for \(dayKey).", "sourceEventIDs": \(jsonArray(idList)) },
          "summaryBulletsToReplace": [
            { "text": "- Appended \(eventIDs.count) onboarding event(s)", "sourceEventIDs": \(jsonArray(idList)) }
          ],
          "detailBlocksToAppend": [
            { "text": "## Chunk \(chunkNumber + 1)\\n\\nProcessed \(eventIDs.count) event(s).", "sourceEventIDs": \(jsonArray(idList)) }
          ],
          "todoItemsToReplace": [
            { "text": "- [ ] Review the next chunk", "sourceEventIDs": \(jsonArray(idList)) }
          ]
        }
        """
    }

    private static func jsonArray(_ values: [String]) -> String {
        let body = values.map { "\"\($0)\"" }.joined(separator: ", ")
        return "[\(body)]"
    }
}

private actor EngineAttemptRecorder {
    private var attempts: [DiaryEngine] = []

    func record(_ engine: DiaryEngine) {
        attempts.append(engine)
    }

    func values() -> [DiaryEngine] {
        attempts
    }
}

private actor ParallelAttemptRecorder {
    private var started: [DiaryEngine] = []
    private var cancelled: [DiaryEngine] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordStart(_ engine: DiaryEngine) {
        started.append(engine)
        if started.contains(.geminiCLI), started.contains(.claudeCLI) {
            let continuations = waiters
            waiters.removeAll()
            continuations.forEach { $0.resume() }
        }
    }

    func waitForGeminiAndClaudeToStart() async {
        if started.contains(.geminiCLI), started.contains(.claudeCLI) {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func recordCancelled(_ engine: DiaryEngine) {
        cancelled.append(engine)
    }

    func snapshot() -> (started: [DiaryEngine], cancelled: [DiaryEngine]) {
        (started, cancelled)
    }
}

private final class RecordingPromptSummarizer: SummaryGenerating, @unchecked Sendable {
    let response: String
    private(set) var capturedDayKey: String?
    private(set) var capturedMarkdown: String?

    init(response: String) {
        self.response = response
    }

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        capturedDayKey = dayKey
        capturedMarkdown = markdown
        return response
    }
}

private struct StubUpdateService: UpdateServing {
    let result: Result<UpdateOffer?, Error>

    func fetchOffer() async throws -> UpdateOffer? {
        try result.get()
    }
}

private struct StubDirectAppUpdater: DirectAppUpdating {
    let handler: @Sendable (UpdateOffer) async throws -> Void

    func startUpdate(for offer: UpdateOffer) async throws {
        try await handler(offer)
    }
}

private final class MainWindowStubURLProtocol: URLProtocol {
    enum Behavior {
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    nonisolated(unsafe) static var behavior: Behavior?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request

        guard let behavior = Self.behavior else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch behavior {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MainWindowStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        behavior = nil
        lastRequest = nil
    }
}

private func requestBodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "MainWindowViewModelTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request body missing"])
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 16 * 1024
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

private final class RecordingNotificationReader: NotificationDatabaseReading, @unchecked Sendable {
    private(set) var requestedSince: Date?
    private(set) var requestedUpperBound: NotificationFetchUpperBound?
    var snapshots: [NotificationSnapshot] = []
    var fetchError: Error?
    var fetchHandler: ((Date, NotificationFetchUpperBound?) throws -> [NotificationSnapshot])?
    var accessStatusValue = NotificationDatabaseAccessStatus(
        state: .available,
        databaseURL: URL(fileURLWithPath: "/tmp/notification-center.sqlite")
    )

    func accessStatus() -> NotificationDatabaseAccessStatus {
        accessStatusValue
    }

    func fetchDeliveredNotifications(from startDate: Date, upperBound: NotificationFetchUpperBound?) throws -> [NotificationSnapshot] {
        requestedSince = startDate
        requestedUpperBound = upperBound
        if let fetchError {
            throw fetchError
        }
        let snapshots: [NotificationSnapshot]
        if let fetchHandler {
            snapshots = try fetchHandler(startDate, upperBound)
        } else {
            snapshots = self.snapshots
        }

        return snapshots.filter { snapshot in
            guard snapshot.deliveredAt >= startDate else {
                return false
            }

            switch upperBound {
            case .exclusive(let endDate):
                return snapshot.deliveredAt < endDate
            case .inclusive(let endDate):
                return snapshot.deliveredAt <= endDate
            case nil:
                return true
            }
        }
    }
}

private final class AppStateTestKeychainStore: KeychainStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String, service: String) {
        values["\(service):\(key)"] = value
    }

    func load(forKey key: String, service: String) -> String? {
        values["\(service):\(key)"]
    }

    func delete(forKey key: String, service: String) {
        values.removeValue(forKey: "\(service):\(key)")
    }
}

private actor ProbeGate {
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ProbeStartTracker {
    private var started: Set<DiaryEngine> = []
    private var waiters: [(Set<DiaryEngine>, CheckedContinuation<Void, Never>)] = []

    func markStarted(_ engine: DiaryEngine) {
        started.insert(engine)
        var remaining: [(Set<DiaryEngine>, CheckedContinuation<Void, Never>)] = []
        for (required, continuation) in waiters {
            if required.isSubset(of: started) {
                continuation.resume()
            } else {
                remaining.append((required, continuation))
            }
        }
        waiters = remaining
    }

    func waitUntilStarted(_ engines: Set<DiaryEngine>) async {
        guard !engines.isSubset(of: started) else { return }
        await withCheckedContinuation { continuation in
            waiters.append((engines, continuation))
        }
    }
}

private actor RefreshBlockGate {
    private var startedCounts: [String: Int] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    func markStarted(dayKey: String) {
        startedCounts[dayKey, default: 0] += 1
        startedWaiters[dayKey]?.resume()
        startedWaiters[dayKey] = nil
    }

    func waitUntilStarted(dayKey: String) async {
        guard startedCounts[dayKey] == nil else { return }
        await withCheckedContinuation { continuation in
            startedWaiters[dayKey] = continuation
        }
    }

    func waitForRelease(dayKey: String) async {
        await withCheckedContinuation { continuation in
            releaseWaiters[dayKey] = continuation
        }
    }

    func release(dayKey: String) {
        releaseWaiters[dayKey]?.resume()
        releaseWaiters[dayKey] = nil
    }

    func startCount(for dayKey: String) -> Int {
        startedCounts[dayKey] ?? 0
    }
}

private struct BlockingSummarizer: SummaryGenerating {
    let gate: RefreshBlockGate

    func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
        await gate.markStarted(dayKey: dayKey)
        await gate.waitForRelease(dayKey: dayKey)
        return """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(dayKey)","sourceEventIDs":[]}]}]}
        """
    }
}

@MainActor
private func makeBlockingRefreshEnvironment() throws -> (AppEnvironment, RefreshBlockGate) {
    let gate = RefreshBlockGate()
    let writer = try DatabaseWriter.inMemory()
    let environment = AppEnvironment(
        databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
        vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
        databaseWriter: writer,
        summarizer: BlockingSummarizer(gate: gate),
        notificationReader: RecordingNotificationReader(),
        dailyAutomationPlanner: DailyAutomationPlanner(
            backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
        )
    )
    return (environment, gate)
}

@MainActor
private final class RefreshStageRecorder {
    private(set) var stages: [DayRefreshStage] = []
    private(set) var jobs: [DayRefreshJob] = []

    func record(_ job: DayRefreshJob) {
        jobs.append(job)
        stages.append(job.stage)
    }
}

private final class ThreadSafeDayKeyCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func setValue(_ value: [String]) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: [String] {
        lock.lock()
        let current = storage
        lock.unlock()
        return current
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
    return await condition()
}

private func waitUntilAsync(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
    return await condition()
}

private func makeValidStoryResponse(sourceEventID: UUID = UUID(), summaryLine: String = "Recovered day") -> String {
    """
    {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(summaryLine)","sourceEventIDs":["\(sourceEventID.uuidString)"]}]}]}
    """
}

private func makeIsolatedCLIProcessEnvironment() throws -> ([String: String], URL) {
    let homeURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    return (
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": homeURL.path,
        ],
        homeURL
    )
}

private final class RecordingLoginItemManager: LoginItemManaging {
    var isRegistered: Bool
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(isRegistered: Bool = false) {
        self.isRegistered = isRegistered
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        isRegistered = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        isRegistered = false
    }
}

private enum RecordingLoginItemError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Login item change denied"
    }
}

@MainActor
final class MainWindowViewModelTests: XCTestCase {
    private var engineDefaultsSuiteName: String!
    private var engineDefaults: UserDefaults!
    private var engineKeychain: AppStateTestKeychainStore!

    private func markOnboardingComplete(in defaults: UserDefaults) {
        defaults.set(true, forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)
        defaults.set(OnboardingProgressState.complete.rawValue, forKey: AppState.UserDefaultsKeys.onboardingProgressState)
        defaults.set(OnboardingBootstrapState.complete.rawValue, forKey: AppState.UserDefaultsKeys.onboardingBootstrapState)
        defaults.removeObject(forKey: AppState.UserDefaultsKeys.onboardingBootstrapDayKeys)
    }

    override func setUp() {
        super.setUp()
        engineDefaultsSuiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        engineDefaults = UserDefaults(suiteName: engineDefaultsSuiteName)!
        engineKeychain = AppStateTestKeychainStore()
        markOnboardingComplete(in: engineDefaults)
        markOnboardingComplete(in: .standard)
    }

    override func tearDown() {
        MainWindowStubURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)
        UserDefaults.standard.removeObject(forKey: AppState.UserDefaultsKeys.onboardingProgressState)
        UserDefaults.standard.removeObject(forKey: AppState.UserDefaultsKeys.onboardingBootstrapState)
        UserDefaults.standard.removeObject(forKey: AppState.UserDefaultsKeys.onboardingBootstrapDayKeys)
        UserDefaults.standard.removeObject(forKey: AppState.UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted)
        if let engineDefaultsSuiteName {
            engineDefaults.removePersistentDomain(forName: engineDefaultsSuiteName)
        }
        super.tearDown()
    }

    func testDefaultLaunchAtLoginRegistersOnce() {
        let loginItemManager = RecordingLoginItemManager(isRegistered: false)
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests",
            loginItemManager: loginItemManager
        )

        appState.ensureDefaultLaunchAtLogin()
        appState.ensureDefaultLaunchAtLogin()

        XCTAssertEqual(loginItemManager.registerCallCount, 1)
        XCTAssertEqual(loginItemManager.unregisterCallCount, 0)
        XCTAssertTrue(appState.launchAtLoginEnabled)
        XCTAssertTrue(engineDefaults.bool(forKey: AppState.UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted))
    }

    func testDefaultLaunchAtLoginDoesNotReenableAfterOptOut() {
        engineDefaults.set(true, forKey: AppState.UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted)
        let loginItemManager = RecordingLoginItemManager(isRegistered: false)
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests",
            loginItemManager: loginItemManager
        )

        appState.ensureDefaultLaunchAtLogin()

        XCTAssertEqual(loginItemManager.registerCallCount, 0)
        XCTAssertFalse(appState.launchAtLoginEnabled)
    }

    func testSettingLaunchAtLoginDisabledUnregistersLoginItem() {
        let loginItemManager = RecordingLoginItemManager(isRegistered: true)
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests",
            loginItemManager: loginItemManager
        )

        appState.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(loginItemManager.unregisterCallCount, 1)
        XCTAssertFalse(appState.launchAtLoginEnabled)
        XCTAssertEqual(appState.launchAtLoginStatusMessage, "Launch at Login disabled")
        XCTAssertTrue(engineDefaults.bool(forKey: AppState.UserDefaultsKeys.launchAtLoginDefaultRegistrationAttempted))
    }

    func testLaunchAtLoginEnableFailureRollsBackToggle() {
        let loginItemManager = RecordingLoginItemManager(isRegistered: false)
        loginItemManager.registerError = RecordingLoginItemError.denied
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests",
            loginItemManager: loginItemManager
        )

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(loginItemManager.registerCallCount, 1)
        XCTAssertFalse(appState.launchAtLoginEnabled)
        XCTAssertEqual(appState.launchAtLoginStatusMessage, "Launch at Login setup failed: Login item change denied")
    }

    @MainActor
    func test_checkForUpdates_setsOfferAndShowsPillWhenNewerVersionExists() throws {
        let environment = try makeEngineEnvironment(updateService: StubUpdateService(result: .success(
            UpdateOffer(
                availableVersion: "1.4.0",
                releaseSummary: "Update pill shipped",
                publishedAt: nil,
                actionKind: .installInApp,
                storeURL: nil,
                downloadURL: URL(string: "https://knowyou.example.com/download")
            )
        )))
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )

        let expectation = expectation(description: "update check")
        Task { @MainActor in
            await appState.checkForUpdatesIfNeeded(force: true)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(appState.updateOffer?.availableVersion, "1.4.0")
        XCTAssertTrue(appState.shouldShowUpdatePill)
    }

    @MainActor
    func test_dismissingUpdateSheet_keepsPillVisible() {
        let appState = AppState(bootstrapServices: false)
        appState.updateOffer = UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .installInApp,
            storeURL: nil,
            downloadURL: URL(string: "https://knowyou.example.com/download")
        )
        appState.isShowingUpdateSheet = true

        appState.dismissUpdateSheet()

        XCTAssertFalse(appState.isShowingUpdateSheet)
        XCTAssertTrue(appState.shouldShowUpdatePill)
    }

    @MainActor
    func test_checkForUpdates_skipsSecondNonForcedCheckOnSameDay() throws {
        let environment = try makeEngineEnvironment(updateService: StubUpdateService(result: .success(
            UpdateOffer(
                availableVersion: "1.4.0",
                releaseSummary: "Update pill shipped",
                publishedAt: nil,
                actionKind: .installInApp,
                storeURL: nil,
                downloadURL: URL(string: "https://knowyou.example.com/download")
            )
        )))
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )

        let date = Date(timeIntervalSince1970: 1_776_000_000)
        let expectation = expectation(description: "same day checks")
        Task { @MainActor in
            await appState.checkForUpdatesIfNeeded(force: false, now: date)
            let firstCheckAt = appState.lastUpdateCheckAt
            await appState.checkForUpdatesIfNeeded(force: false, now: date.addingTimeInterval(60))
            XCTAssertEqual(appState.lastUpdateCheckAt, firstCheckAt)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    @MainActor
    func test_openUpdateSheet_onlyOpensWhenOfferExists() {
        let appState = AppState(bootstrapServices: false)

        appState.openUpdateSheet()
        XCTAssertFalse(appState.isShowingUpdateSheet)

        appState.updateOffer = UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .openAppStore,
            storeURL: URL(string: "https://apps.apple.com/app/id123")
        )

        appState.openUpdateSheet()
        XCTAssertTrue(appState.isShowingUpdateSheet)
    }

    @MainActor
    func test_performUpdatePrimaryAction_marksProgressForDirectInstall() throws {
        let updateStarted = expectation(description: "direct update started")
        let environment = try makeEngineEnvironment(
            directAppUpdater: StubDirectAppUpdater { offer in
                XCTAssertEqual(offer.availableVersion, "1.4.0")
                updateStarted.fulfill()
            }
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        appState.updateOffer = UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .installInApp,
            storeURL: nil,
            downloadURL: URL(string: "https://knowyou.example.com/download")
        )

        appState.performUpdatePrimaryAction()

        wait(for: [updateStarted], timeout: 2.0)
        XCTAssertEqual(appState.statusMessage, "Opening update download...")
    }

    @MainActor
    func test_performUpdatePrimaryAction_usesInjectedExternalURLOpenerForAppStoreOffer() throws {
        let openedStore = expectation(description: "store url opened")
        let environment = try makeEngineEnvironment(
            externalURLOpener: { url in
                XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id123")
                openedStore.fulfill()
            }
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        appState.updateOffer = UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .openAppStore,
            storeURL: URL(string: "https://apps.apple.com/app/id123"),
            downloadURL: nil
        )
        appState.isShowingUpdateSheet = true

        appState.performUpdatePrimaryAction()

        wait(for: [openedStore], timeout: 2.0)
        XCTAssertFalse(appState.isShowingUpdateSheet)
    }

    @MainActor
    func test_performUpdatePrimaryAction_usesDefaultDirectDownloaderWhenConfigured() throws {
        let openedDownload = expectation(description: "download url opened")
        let environment = try makeEngineEnvironment(
            externalURLOpener: { url in
                XCTAssertEqual(url.absoluteString, "https://knowyou.example.com/download")
                openedDownload.fulfill()
            }
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        appState.updateOffer = UpdateOffer(
            availableVersion: "1.4.0",
            releaseSummary: "Update pill shipped",
            publishedAt: nil,
            actionKind: .installInApp,
            storeURL: nil,
            downloadURL: URL(string: "https://knowyou.example.com/download")
        )

        appState.performUpdatePrimaryAction()

        wait(for: [openedDownload], timeout: 2.0)
        XCTAssertFalse(appState.isShowingUpdateSheet)
    }

    func testSelectingDateLoadsMatchingMarkdownPath() {
        let appState = AppState(bootstrapServices: false)
        appState.availableDates = ["2026-04-07", "2026-04-06"]
        appState.noteIndex = [
            "2026-04-07": URL(fileURLWithPath: "/tmp/2026-04-07.md"),
            "2026-04-06": URL(fileURLWithPath: "/tmp/2026-04-06.md"),
        ]

        appState.selectDate("2026-04-06")

        XCTAssertEqual(appState.selectedDate, "2026-04-06")
        XCTAssertEqual(appState.selectedMarkdownURL?.path, "/tmp/2026-04-06.md")
    }

    func testSelectingDateWithoutIndexedFileClearsMarkdownPath() {
        let appState = AppState(bootstrapServices: false)
        appState.selectedMarkdownURL = URL(fileURLWithPath: "/tmp/existing.md")

        appState.selectDate("2026-04-08")

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertNil(appState.selectedMarkdownURL)
    }

    func testSelectingDateLoadsSourceNotesMarkdownFromSavedFile() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied

            Saved in the source notebook.
            """
        )
    }

    func testSelectingDateFallsBackToGeneratedSourceNotesWhenMarkdownFileIsMissing() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        let fileURL = environment.vaultURL.appending(path: "2026-04-08.md")
        try FileManager.default.removeItem(at: fileURL)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }

    func testSelectingDateFallsBackToGeneratedSourceNotesWhenSavedMarkdownHasNoSourceNotesSection() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        let fileURL = environment.vaultURL.appending(path: "2026-04-08.md")
        try """
        # 2026-04-08

        ## Story

        First paragraph with **bold** emphasis.

        ## Appendix

        This file was saved without source notes.
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }

    func testSelectingChineseDateLoadsLocalizedSourceNotesMarkdown() throws {
        let environment = try makeChineseReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)

        appState.selectDate("2026-04-09")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """
        )
    }

    func testSelectingChineseDateFallsBackToLocalizedGeneratedSourceNotesWhenMarkdownFileIsMissing() throws {
        let environment = try makeChineseReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        let fileURL = environment.vaultURL.appending(path: "2026-04-09.md")
        try FileManager.default.removeItem(at: fileURL)

        appState.selectDate("2026-04-09")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """
        )
    }

    func testAutomationStatusTextReflectsManualOnlyHistoryPolicy() {
        let appState = AppState(bootstrapServices: false)
        appState.lastImportedNotificationCount = 3
        appState.pendingBackfillDays = ["2026-04-06", "2026-04-07"]

        XCTAssertTrue(appState.automationStatusText.contains("Notifications: 3"))
        XCTAssertTrue(appState.automationStatusText.contains("History refresh is manual-only"))
    }

    func testGenerateDailyNoteFailsWithoutPersistingFilesWhenSummarizerFails() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = Date(timeIntervalSince1970: 1_775_000_000)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-07",
                text: "Ship feature",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "note-hash"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: ThrowingSummarizer(),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.generateDailyNote(for: "2026-04-07")

        let savedURL = vaultURL.appending(path: "2026-04-07.md")
        let storyURL = vaultURL.appending(path: "2026-04-07.story.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storyURL.path))
        XCTAssertTrue(appState.statusMessage?.contains("Daily note failed:") == true)
        XCTAssertEqual(appState.summarizerStatus.lastError, URLError(.cannotConnectToHost).localizedDescription)
        XCTAssertNil(appState.selectedStory)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "failed")
    }

    func testGenerateDailyNotePreservesExistingModelStoryWhenNoNewEventsExist() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-07"
        let capturedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
                text: "Ship feature",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "note-hash"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: ThrowingSummarizer(),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        let existingStory = makeModelStory(dayKey: dayKey, eventID: eventID)
        let existingMarkdown = "# Existing model story\nStill good."
        _ = try environment.writeDailyNote(dayKey: dayKey, markdown: existingMarkdown)
        _ = try environment.writeDailyStory(existingStory)

        await appState.generateDailyNote(for: dayKey)

        let savedURL = vaultURL.appending(path: "\(dayKey).md")
        let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), existingMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertEqual(appState.statusMessage, "Refreshed \(dayKey)")
        XCTAssertNil(appState.dayRefreshStatus.lastError)
        XCTAssertEqual(appState.dayRefreshStatus.detail, "No new events to append for \(dayKey)")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.detail, "Completed · No new events")
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
        XCTAssertEqual(try JSONDecoder().decode(DailyStory.self, from: Data(contentsOf: storyURL)), existingStory)
    }

    func testRunAutomationImportsNotificationsFromStartOfToday() async throws {
        let writer = try DatabaseWriter.inMemory()
        let completedRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-01")
        try writer.finishRun(id: completedRun, status: "succeeded")

        let reader = RecordingNotificationReader()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(
            ISO8601DayKey.format(reader.requestedSince ?? .distantPast),
            "2026-04-07"
        )
    }

    func testRunAutomationFullRecoversTodayWhenOnlyMarkdownAlreadyExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let today = "2026-04-07"
        let capturedAt = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 4,
            day: 7,
            hour: 9
        ).date!

        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: today,
                text: "Fresh clipboard entry",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "fresh-entry"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let existingNoteURL = vaultURL.appending(path: "\(today).md")
        try "stale note".write(to: existingNoteURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(now: capturedAt)

        let rebuiltMarkdown = try String(contentsOf: existingNoteURL)
        XCTAssertNotEqual(rebuiltMarkdown, "stale note")
        XCTAssertEqual(appState.selectedDate, today)
        XCTAssertEqual(
            appState.selectedMarkdownURL?.standardizedFileURL.path,
            existingNoteURL.standardizedFileURL.path
        )
        XCTAssertEqual(try environment.loadDailyStory(dayKey: today)?.provenance?.generationMode, .model)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
    }

    func testRunAutomationFullRecoversTodayWhenNoModelStoryExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        let capturedAt = DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
                text: "Fresh start for the day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-first-full-recovery"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Automation created the first story")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey)?.provenance?.generationMode, .model)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.status, "succeeded")
    }

    func testRunAutomationWithoutVerifiedEnginePromptsConfigurationForFreshToday() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!,
                dayKey: dayKey,
                text: "Need an engine before automation can write",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-no-engine"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        XCTAssertEqual(appState.statusMessage, "Configure and verify an engine to generate today's journal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertNil(try writer.fetchRuns(runType: "daily-note").last)
    }

    func testSummaryGeneratingIncrementalFallbackUsesPlainSummarizeImplementation() async throws {
        let concreteSummarizer = RecordingPlainSummarizer(response: "incremental payload")
        let summarizer: any SummaryGenerating = concreteSummarizer

        let result = try await summarizer.summarizeIncremental(
            dayKey: "2026-04-14",
            markdown: "Incremental prompt body",
            context: .manualRefresh
        )

        XCTAssertEqual(result, "incremental payload")
        let snapshot = await concreteSummarizer.recorder.snapshot()
        XCTAssertEqual(snapshot.callCount, 1)
        XCTAssertEqual(snapshot.dayKey, "2026-04-14")
        XCTAssertEqual(snapshot.markdown, "Incremental prompt body")
        XCTAssertEqual(snapshot.context, .manualRefresh)
    }

    func testCloudSummarizerIncrementalPreservesPromptContract() async throws {
        MainWindowStubURLProtocol.behavior = .success(
            statusCode: 200,
            body: Data(#"{"output_text":"incremental ok"}"#.utf8)
        )
        let summarizer = CloudSummarizer(
            apiKey: "test-key",
            session: MainWindowStubURLProtocol.makeSession(),
            model: "gpt-5"
        )
        let incrementalPrompt = """
        Existing diary state goes here.
        Add only the new events with replacement-and-append semantics.
        """

        let result = try await summarizer.summarizeIncremental(
            dayKey: "2026-04-14",
            markdown: incrementalPrompt,
            context: .manualRefresh
        )

        XCTAssertEqual(result, "incremental ok")
        let request = try XCTUnwrap(MainWindowStubURLProtocol.lastRequest)
        let body = try requestBodyData(from: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "gpt-5")
        XCTAssertEqual(object["input"] as? String, incrementalPrompt)
    }

    func testRunAutomationIncrementallyReplacesAndAppendsTodayWhenModelStoryHasNewEvents() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-07"
        let oldID = UUID()
        let newID = UUID()
        let oldEvent = EventRecord(
            id: oldID,
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 9).date!,
            dayKey: dayKey,
            text: "Wrapped the first pass",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "old-event"
        )
        let newEvent = EventRecord(
            id: newID,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 11).date!,
            dayKey: dayKey,
            text: "Customer approved the follow-up",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "new-event"
        )
        try writer.insert(oldEvent)
        try writer.insert(newEvent)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let initialStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldEvent], story: initialStory),
            story: initialStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: newID, summaryLine: "Unexpected full refresh"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
              "summaryBulletsToReplace": [
                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
              ],
              "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ]
            }
            """
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return summarizer
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Ready.",
            lastVerifiedAt: Date(),
            configurationSignature: "codex"
        )

        await appState.runAutomation(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 12).date!)

        let markdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(markdown.contains("Closed strong."))
        XCTAssertTrue(markdown.contains("- Customer approved the follow-up"))
        XCTAssertFalse(markdown.contains("- Wrapped the first pass"))
        XCTAssertFalse(markdown.contains("- [ ] Send recap"))
        XCTAssertFalse(markdown.contains("Keep the pace."))
        XCTAssertTrue(markdown.contains("## Existing Thread"))
        XCTAssertTrue(markdown.contains("## Follow-up"))
        XCTAssertTrue(markdown.contains("- [ ] Queue the final handoff"))
        let counts = await summarizer.recorder.counts()
        XCTAssertEqual(counts.summarize, 0)
        XCTAssertEqual(counts.summarizeIncremental, 1)
        XCTAssertEqual(try writer.fetchRuns(runType: "daily-note").last?.dayKey, dayKey)
    }

    func testRunNotificationCatchUpRecoversTodayNotificationsFromStartOfDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let dayKey = ISO8601DayKey.format(now)
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: now)

        XCTAssertEqual(reader.requestedSince, calendar.startOfDay(for: now))
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(try writer.fetchEvents(dayKey: dayKey).count, 1)
        XCTAssertEqual(appState.lastNotificationImportAt, now)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
    }

    func testRunNotificationCatchUpUsesOverlapBufferWithoutDuplicatingNotifications() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let firstNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let secondNow = firstNow.addingTimeInterval(120)
        let repeatedNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: firstNow.addingTimeInterval(-15),
            body: "Same delivered notification"
        )
        reader.fetchHandler = { startDate, upperBound in
            switch upperBound {
            case .inclusive(let endDate):
                if endDate == firstNow {
                    return [repeatedNotification]
                }
                if endDate == secondNow {
                    XCTAssertEqual(startDate, firstNow.addingTimeInterval(-30))
                    return [repeatedNotification]
                }
                return []
            case .exclusive, nil:
                return []
            }
        }

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: firstNow)
        await appState.runNotificationCatchUp(now: secondNow)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(firstNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(secondNow))
        XCTAssertEqual(appState.lastNotificationImportAt, secondNow)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
    }

    func testRunNotificationCatchUpDoesNotPersistWatermarkWhenNotificationDatabaseUnavailable() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.accessStatusValue = NotificationDatabaseAccessStatus(state: .missing, databaseURL: nil)
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.runNotificationCatchUp(now: now)

        XCTAssertNil(appState.lastNotificationImportAt)
        XCTAssertNil(engineDefaults.object(forKey: AppState.UserDefaultsKeys.lastNotificationImportAt))
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 0)
    }

    func testStartAutomationStillRunsTodayOnlyAutomationWhileSchedulingCatchUp() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13).date!
        let dayKey = ISO8601DayKey.format(now)
        let reader = RecordingNotificationReader()
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Clipboard event for automation",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "automation-startup-event"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            currentDate: { now },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.startAutomation()

        let automationStarted = await waitUntil {
            appState.lastAutomationRunAt == now
        }
        XCTAssertTrue(automationStarted)
        XCTAssertEqual(appState.lastAutomationRunAt, now)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertNil(try writer.fetchRuns(runType: "daily-note").last)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
    }

    func testRelaunchRestoresPersistedLastNotificationImportAtForCatchUpWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let firstReader = RecordingNotificationReader()
        let initialNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let resumedNow = initialNow.addingTimeInterval(120)
        let overlapStart = initialNow.addingTimeInterval(-30)
        let sharedDatabaseURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite")
        let repeatedNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: initialNow.addingTimeInterval(-10),
            body: "Persist across relaunch"
        )
        firstReader.snapshots = [repeatedNotification]

        let environment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: firstReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let original = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { initialNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await original.runNotificationCatchUp(now: initialNow)

        let secondReader = RecordingNotificationReader()
        secondReader.fetchHandler = { startDate, upperBound in
            XCTAssertEqual(startDate, overlapStart)
            XCTAssertEqual(upperBound, .inclusive(resumedNow))
            return [repeatedNotification]
        }
        let relaunchedEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: secondReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let relaunched = AppState(
            environment: relaunchedEnvironment,
            bootstrapServices: false,
            currentDate: { resumedNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(relaunched.lastNotificationImportAt, initialNow)

        await relaunched.runNotificationCatchUp(now: resumedNow)

        let events = try writer.fetchEvents(dayKey: ISO8601DayKey.format(initialNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(relaunched.lastNotificationImportAt, resumedNow)
    }

    func testRelaunchWithFreshStoreIgnoresPersistedNotificationWatermark() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let initialNow = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 13, minute: 0, second: 0).date!
        let resumedNow = initialNow.addingTimeInterval(120)
        let sharedDatabaseURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite")
        let originalWriter = try DatabaseWriter.inMemory()
        let originalReader = RecordingNotificationReader()
        let originalNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: initialNow.addingTimeInterval(-10),
            body: "Persist across relaunch"
        )
        originalReader.snapshots = [originalNotification]
        let originalEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: originalWriter,
            summarizer: nil,
            notificationReader: originalReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let original = AppState(
            environment: originalEnvironment,
            bootstrapServices: false,
            currentDate: { initialNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await original.runNotificationCatchUp(now: initialNow)

        let freshWriter = try DatabaseWriter.inMemory()
        let freshReader = RecordingNotificationReader()
        let freshNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 9, minute: 0).date!,
            body: "Earlier same-day notification in fresh store"
        )
        freshReader.fetchHandler = { startDate, upperBound in
            XCTAssertEqual(startDate, calendar.startOfDay(for: resumedNow))
            XCTAssertEqual(upperBound, .inclusive(resumedNow))
            return [freshNotification]
        }
        let freshEnvironment = AppEnvironment(
            databaseURL: sharedDatabaseURL,
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: freshWriter,
            summarizer: nil,
            notificationReader: freshReader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let relaunched = AppState(
            environment: freshEnvironment,
            bootstrapServices: false,
            currentDate: { resumedNow },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertNil(relaunched.lastNotificationImportAt)

        await relaunched.runNotificationCatchUp(now: resumedNow)

        let events = try freshWriter.fetchEvents(dayKey: ISO8601DayKey.format(initialNow))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.text, freshNotification.body)
        XCTAssertEqual(relaunched.lastNotificationImportAt, resumedNow)
    }

    func testRefreshSelectedDayForTodayRequestsOnlyTodayWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let priorRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-09")
        try writer.finishRun(id: priorRun, status: "succeeded")
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        XCTAssertEqual(reader.requestedSince, calendar.startOfDay(for: now))
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(appState.selectedDate, "2026-04-11")
    }

    func testRefreshSelectedDayForTodayIgnoresFutureNotificationsLaterThatDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = ISO8601DayKey.format(now)
        let beforeNowNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 14, minute: 45).date!,
            body: "Already happened"
        )
        let afterNowNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 18, minute: 0).date!,
            body: "Future in day"
        )
        reader.fetchHandler = { _, _ in [beforeNowNotification, afterNowNotification] }

        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-event-with-future-filter"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        let events = try writer.fetchEvents(dayKey: dayKey)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertTrue(events.contains(where: { $0.sourceType == .notification && $0.text == beforeNowNotification.body }))
        XCTAssertFalse(events.contains(where: { $0.sourceType == .notification && $0.text == afterNowNotification.body }))
    }

    func testRefreshSelectedDayForHistoricalDateRequestsOnlyThatDayWindow() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectDate("2026-04-08")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!
        )

        let expectedStart = DateComponents(calendar: calendar, year: 2026, month: 4, day: 8).date!
        let expectedEnd = calendar.date(byAdding: .day, value: 1, to: expectedStart)
        XCTAssertEqual(reader.requestedSince, expectedStart)
        XCTAssertEqual(reader.requestedUpperBound, expectedEnd.map(NotificationFetchUpperBound.exclusive))
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
    }

    func testRefreshSelectedDayDoesNotRunMultiDayAutomationBackfill() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let priorRun = try writer.startRun(runType: "daily-note", dayKey: "2026-04-09")
        try writer.finishRun(id: priorRun, status: "succeeded")
        let selectedDay = "2026-04-08"
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        reader.snapshots = [
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 8, hour: 9).date!,
                body: "Standup in 5"
            )
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Selected day refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectDate(selectedDay)

        let runsBeforeRefresh = try writer.fetchRuns(runType: "daily-note").count

        await appState.refreshSelectedDay(now: now)

        let runDaysAfterRefresh = try writer.fetchRuns(runType: "daily-note").map(\.dayKey)
        XCTAssertEqual(runDaysAfterRefresh.count, runsBeforeRefresh + 1)
        XCTAssertEqual(runDaysAfterRefresh.last, selectedDay)
        XCTAssertEqual(appState.selectedDate, selectedDay)
    }

    func testRefreshSelectedDayDoesNotCallAutomationPath() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        reader.snapshots = [
            NotificationSnapshot(
                appName: "Calendar",
                deliveredAt: now,
                body: "Standup in 5"
            )
        ]

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        XCTAssertNil(appState.lastAutomationRunAt)
    }

    func testRefreshSelectedDayUsesTodayWhenNoSelectionExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 10).date!
        let dayKey = ISO8601DayKey.format(now)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-event"
            )
        )
        reader.snapshots = [
            NotificationSnapshot(appName: "Calendar", deliveredAt: now, body: "Standup in 5")
        ]

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today refreshed")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        XCTAssertEqual(appState.selectedDate, dayKey)
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(appState.statusMessage, "Imported 1 notifications and refreshed today")
    }

    func testRefreshSelectedDayForHistoricalSelectionImportsOnlyThatDayNotifications() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        let calendar = Calendar(identifier: .gregorian)
        let historicalDay = "2026-04-06"
        let historicalStart = DateComponents(calendar: calendar, year: 2026, month: 4, day: 6).date!
        let capturedAt = DateComponents(calendar: calendar, year: 2026, month: 4, day: 6, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: historicalDay,
                text: "Backfill me",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "historical-event"
            )
        )
        let historicalNotification = NotificationSnapshot(
            appName: "Mail",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 6, hour: 14).date!,
            body: "Historical notification"
        )
        let outsideDayNotification = NotificationSnapshot(
            appName: "Calendar",
            deliveredAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7, hour: 8).date!,
            body: "Should not leak into 2026-04-06"
        )
        reader.fetchHandler = { _, _ in [historicalNotification, outsideDayNotification] }

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectDate(historicalDay)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 7).date!)

        let historicalEvents = try writer.fetchEvents(dayKey: historicalDay)
        XCTAssertEqual(reader.requestedSince, historicalStart)
        XCTAssertEqual(
            reader.requestedUpperBound,
            calendar.date(byAdding: .day, value: 1, to: historicalStart).map(NotificationFetchUpperBound.exclusive)
        )
        XCTAssertEqual(appState.notificationStatus.lastImportedCount, 1)
        XCTAssertEqual(historicalEvents.count, 2)
        XCTAssertTrue(historicalEvents.contains(where: { $0.sourceType == .notification && $0.text == historicalNotification.body }))
        XCTAssertEqual(try writer.fetchEvents(dayKey: "2026-04-07").count, 0)
        XCTAssertFalse(historicalEvents.contains(where: { $0.sourceType == .notification && $0.text == outsideDayNotification.body }))
        XCTAssertEqual(appState.selectedDate, historicalDay)
    }

    func testReaderNavigationRestoresPerDayParagraphMemory() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.refreshNotesIndex()

        XCTAssertEqual(appState.readerFocus, .dateList)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")

        appState.handleReaderMove(.right)
        appState.selectStoryParagraph("daily-journal-1")
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-1")

        appState.handleReaderMove(.left)
        XCTAssertEqual(appState.readerFocus, .dateList)

        appState.handleReaderMove(.down)
        XCTAssertEqual(appState.selectedDate, "2026-04-07")
        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-0")

        appState.handleReaderMove(.left)
        appState.handleReaderMove(.up)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-1")
    }

    func testEscapeReturnsStoryFocusToDateList() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.refreshNotesIndex()

        appState.handleReaderMove(.right)
        XCTAssertEqual(appState.readerFocus, .storyParagraphs)

        appState.handleReaderExit()

        XCTAssertEqual(appState.readerFocus, .dateList)
        XCTAssertEqual(appState.selectedDate, "2026-04-08")
    }

    func testStatusDetailsExplainClipboardAndNotificationSources() {
        let appState = AppState(bootstrapServices: false)
        appState.clipboardStatus.isActive = true
        appState.notificationStatus.isDatabaseAvailable = false
        appState.notificationStatus.availabilityMessage = "Notification Center database not found on this Mac."

        let details = appState.statusDetails

        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("pasteboard") }))
        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("not maccy") }))
        XCTAssertTrue(details.contains(where: { $0.localizedCaseInsensitiveContains("notification center") }))
    }

    private func makeReaderEnvironment() throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )

        let firstID = UUID()
        let secondID = UUID()
        let baseCalendar = Calendar(identifier: .gregorian)
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 8, hour: 9, minute: 0).date!,
                dayKey: "2026-04-08",
                text: "Important note",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-first"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 8, hour: 9, minute: 15).date!,
                dayKey: "2026-04-08",
                text: "Investor replied",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "source-note-second"
            )
        )

        try writeStoryDay(
            dayKey: "2026-04-08",
            markdown: """
            # 2026-04-08

            ## Story

            First paragraph with **bold** emphasis.

            Second paragraph with a [link](https://example.com).

            ---

            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied

            Saved in the source notebook.
            """,
            story: DailyStory(
                dayKey: "2026-04-08",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "First paragraph with **bold** emphasis.", sourceEventIDs: [firstID]),
                            DailyStoryParagraph(id: "daily-journal-1", text: "Second paragraph with a [link](https://example.com).", sourceEventIDs: [secondID]),
                        ]
                    )
                ]
            ),
            environment: environment
        )

        try writeStoryDay(
            dayKey: "2026-04-07",
            markdown: "# 2026-04-07\n\nStory",
            story: DailyStory(
                dayKey: "2026-04-07",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "Only paragraph", sourceEventIDs: [UUID()])
                        ]
                    )
                ]
            ),
            environment: environment
        )

        return environment
    }

    private func makeChineseReaderEnvironment() throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )

        let firstID = UUID()
        let secondID = UUID()
        let baseCalendar = Calendar(identifier: .gregorian)
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "微信",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 9, hour: 10, minute: 0).date!,
                dayKey: "2026-04-09",
                text: "今天要先处理发货",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "cn-source-note-first"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .notification,
                sourceApp: "邮件",
                capturedAt: DateComponents(calendar: baseCalendar, year: 2026, month: 4, day: 9, hour: 10, minute: 15).date!,
                dayKey: "2026-04-09",
                text: "客户确认了收货时间",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "cn-source-note-second"
            )
        )

        try writeStoryDay(
            dayKey: "2026-04-09",
            markdown: """
            # 2026-04-09

            ## 今日小记

            上午主要在处理发货和确认时间。

            ---

            ## 线索来源

            - [10:00] 微信 (clipboard): 今天要先处理发货
            - [10:15] 邮件 (notification): 客户确认了收货时间
            """,
            story: DailyStory(
                dayKey: "2026-04-09",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "上午主要在处理发货和确认时间。", sourceEventIDs: [firstID, secondID]),
                        ]
                    )
                ]
            ),
            environment: environment
        )

        return environment
    }

    private func writeStoryDay(dayKey: String, markdown: String, story: DailyStory, environment: AppEnvironment) throws {
        _ = try environment.writeDailyNote(dayKey: dayKey, markdown: markdown)
        _ = try environment.writeDailyStory(story)
    }

    func testRunAutomationSurfacesNotificationImportError() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.fetchError = CocoaError(.fileReadUnknown)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7).date!)

        XCTAssertEqual(appState.notificationStatus.lastError, CocoaError(.fileReadUnknown).localizedDescription)
    }

    func testRunAutomationDoesNotBackfillHistoricalDays() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let writer = try DatabaseWriter.inMemory()
        let runID = try writer.startRun(runType: "daily-note", dayKey: "2026-04-08")
        try writer.finishRun(id: runID, status: "succeeded")

        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 10).date!,
                dayKey: "2026-04-09",
                text: "Historical gap event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "historical-gap-event"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Should stay manual-only")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.runAutomation(
            now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 10, hour: 12).date!
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appending(path: "2026-04-09.md").path))
        XCTAssertTrue(appState.pendingBackfillDays.isEmpty)
    }

    func testRefreshSelectedDayDoesNotMaskTodayGenerationFailure() async throws {
        let writer = try DatabaseWriter.inMemory()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 10).date!
        let dayKey = ISO8601DayKey.format(now)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-failure"
            )
        )

        let vaultFileURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try "not a directory".write(to: vaultFileURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultFileURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        XCTAssertTrue(appState.statusMessage?.contains("Daily note failed:") == true)
        XCTAssertNotNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayStillGeneratesTodayWhenNotificationImportFails() async throws {
        let writer = try DatabaseWriter.inMemory()
        let reader = RecordingNotificationReader()
        reader.fetchError = CocoaError(.fileReadUnknown)
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 10).date!
        let dayKey = ISO8601DayKey.format(now)
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: dayKey,
                text: "Today event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "today-import-failure"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Today kept despite notification failure")),
            notificationReader: reader,
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.refreshSelectedDay(now: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultURL.appending(path: "\(dayKey).md").path))
        XCTAssertEqual(appState.dayRefreshStatus.lastError, nil)
        XCTAssertEqual(reader.requestedUpperBound, .inclusive(now))
        XCTAssertEqual(appState.notificationStatus.lastError, CocoaError(.fileReadUnknown).localizedDescription)
        XCTAssertEqual(
            appState.statusMessage,
            "Refreshed today without notifications: \(CocoaError(.fileReadUnknown).localizedDescription)"
        )
    }

    func testRefreshSelectedDayWritesRefreshLogFile() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Log this refresh",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-log-file"
            )
        )

        let supportURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: supportURL.appending(path: "events.sqlite"),
            vaultURL: supportURL.appending(path: "Vault", directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Loggable refresh")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let logDirectory = supportURL.appending(path: "RefreshLogs", directoryHint: .isDirectory)
        let logFiles = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(logFiles.count, 1)

        let data = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["dayKey"] as? String, dayKey)
        XCTAssertEqual(object["trigger"] as? String, "manual")
        XCTAssertEqual(object["mode"] as? String, "fullRecovery")
        XCTAssertEqual(object["finalStatus"] as? String, "completed")
        XCTAssertEqual((object["attempts"] as? [[String: Any]])?.count, 1)
    }

    func testRefreshSelectedDaySurfacesRefreshLogWriteFailure() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Log failure should stay visible but low-key",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-log-failure"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/dev/null/events.sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Refresh succeeds even if log writing does not")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        XCTAssertEqual(appState.refreshLogNotice(for: dayKey), "Refresh log unavailable")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .completed)
    }

    func testRefreshSelectedDayIncrementallyReplacesAndAppendsToModelStory() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        let oldEvent = EventRecord(
            id: oldID,
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
            dayKey: dayKey,
            text: "Wrapped the first pass",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "incremental-old"
        )
        let newEvent = EventRecord(
            id: newID,
            sourceType: .notification,
            sourceApp: "Mail",
            capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
            dayKey: dayKey,
            text: "Customer approved the follow-up",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "incremental-new"
        )
        try writer.insert(oldEvent)
        try writer.insert(newEvent)

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldEvent], story: existingStory),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: newID, summaryLine: "Unexpected full refresh"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
              "summaryBulletsToReplace": [
                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
              ],
              "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ]
            }
            """
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return summarizer
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Closed strong."))
        XCTAssertTrue(refreshedMarkdown.contains("- Customer approved the follow-up"))
        XCTAssertFalse(refreshedMarkdown.contains("Keep the old pace."))
        XCTAssertFalse(refreshedMarkdown.contains("- Wrapped the first pass"))
        XCTAssertTrue(refreshedMarkdown.contains("## Existing Thread"))
        XCTAssertTrue(refreshedMarkdown.contains("## Follow-up"))
        XCTAssertTrue(refreshedMarkdown.contains("- [ ] Queue the final handoff"))
        XCTAssertFalse(refreshedMarkdown.contains("- [ ] Send recap"))
        let counts = await summarizer.recorder.counts()
        XCTAssertEqual(counts.summarize, 0)
        XCTAssertEqual(counts.summarizeIncremental, 1)
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testGenerateDailyNoteUsesIncrementalModeWhenModelStoryExists() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "generate-note-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 10).date!,
                dayKey: dayKey,
                text: "Queued the final handoff",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "generate-note-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(dayKey: dayKey, events: [oldID, newID].compactMap { id in
                try? writer.fetchEvents(dayKey: dayKey).first(where: { $0.id == id })
            }, story: existingStory),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: newID, summaryLine: "Unexpected full refresh"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
              "summaryBulletsToReplace": [
                { "text": "- Queued the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ],
              "detailBlocksToAppend": [],
              "todoItemsToReplace": [
                { "text": "- [ ] Finish the handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ]
            }
            """
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return summarizer
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")

        await appState.generateDailyNote(for: dayKey)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Closed strong."))
        XCTAssertTrue(refreshedMarkdown.contains("- Queued the final handoff"))
        XCTAssertTrue(refreshedMarkdown.contains("- [ ] Finish the handoff"))
        XCTAssertFalse(refreshedMarkdown.contains("Keep the old pace."))
        XCTAssertFalse(refreshedMarkdown.contains("- Wrapped the first pass"))
        XCTAssertFalse(refreshedMarkdown.contains("- [ ] Send recap"))
        XCTAssertFalse(refreshedMarkdown.contains("Recovered day"))
        let counts = await summarizer.recorder.counts()
        XCTAssertEqual(counts.summarize, 0)
        XCTAssertEqual(counts.summarizeIncremental, 1)
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testGenerateDailyNoteFullRecoveryStillUsesSummarizeAPI() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-10"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 10, hour: 9).date!,
                dayKey: dayKey,
                text: "Recover the day from scratch",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-api"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: eventID, summaryLine: "Recovered through full path"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Should not be used.", "sourceEventIDs": ["\(eventID.uuidString)"] },
              "summaryBulletsToReplace": [{ "text": "- Wrong path", "sourceEventIDs": ["\(eventID.uuidString)"] }],
              "detailBlocksToAppend": [],
              "todoItemsToReplace": []
            }
            """
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectedDate = nil
        appState.selectedStory = nil

        await appState.generateDailyNote(for: dayKey)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Recovered through full path"))
        XCTAssertFalse(refreshedMarkdown.contains("Wrong path"))
        let counts = await summarizer.recorder.counts()
        XCTAssertEqual(counts.summarize, 1)
        XCTAssertEqual(counts.summarizeIncremental, 0)
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayIncrementalParallelFallbackKeepsSlowerValidResultAfterFasterMalformedResult() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "parallel-incremental-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "parallel-incremental-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(
                dayKey: dayKey,
                events: try writer.fetchEvents(dayKey: dayKey),
                story: existingStory
            ),
            story: existingStory,
            environment: environment
        )

        let attemptRecorder = ParallelAttemptRecorder()
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                let attemptEngine = engine
                return HandlerIncrementalSummarizer(
                    summarizeHandler: { _, _, _ in "Unexpected full refresh" },
                    summarizeIncrementalHandler: { _, _, _ in
                        await attemptRecorder.recordStart(attemptEngine)
                        switch attemptEngine {
                        case .codexCLI:
                            return "not json"
                        case .geminiCLI:
                            await attemptRecorder.waitForGeminiAndClaudeToStart()
                            return """
                            {
                              "encouragementToReplace": { "text": "bad payload" },
                              "summaryBulletsToReplace": [],
                              "detailBlocksToAppend": [],
                              "todoItemsToReplace": []
                            }
                            """
                        case .claudeCLI:
                            try await Task.sleep(nanoseconds: 100_000_000)
                            return """
                            {
                              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                              "summaryBulletsToReplace": [
                                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
                              ],
                              "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
                              "todoItemsToReplace": [
                                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                              ]
                            }
                            """
                        default:
                            throw URLError(.cannotConnectToHost)
                        }
                    }
                )
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.engineStatuses[.claudeCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "claude")
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "gemini")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let snapshot = await attemptRecorder.snapshot()
        XCTAssertTrue(snapshot.started.contains(.geminiCLI))
        XCTAssertTrue(snapshot.started.contains(.claudeCLI))
        XCTAssertTrue(snapshot.cancelled.isEmpty)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Closed strong."))
        XCTAssertTrue(refreshedMarkdown.contains("- Customer approved the follow-up"))
        XCTAssertTrue(refreshedMarkdown.contains("## Follow-up"))
        XCTAssertFalse(refreshedMarkdown.contains("bad payload"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayIncrementalParallelFallbackCancelsSlowerEngineAfterFirstValidResult() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "parallel-cancel-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "parallel-cancel-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(
                dayKey: dayKey,
                events: try writer.fetchEvents(dayKey: dayKey),
                story: existingStory
            ),
            story: existingStory,
            environment: environment
        )

        let attemptRecorder = ParallelAttemptRecorder()
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                let attemptEngine = engine
                return HandlerIncrementalSummarizer(
                    summarizeHandler: { _, _, _ in "Unexpected full refresh" },
                    summarizeIncrementalHandler: { _, _, _ in
                        await attemptRecorder.recordStart(attemptEngine)
                        switch attemptEngine {
                        case .codexCLI:
                            return "not json"
                        case .geminiCLI:
                            await attemptRecorder.waitForGeminiAndClaudeToStart()
                            return """
                            {
                              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                              "summaryBulletsToReplace": [
                                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
                              ],
                              "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
                              "todoItemsToReplace": [
                                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
                              ]
                            }
                            """
                        case .claudeCLI:
                            do {
                                try await Task.sleep(nanoseconds: 5_000_000_000)
                                return """
                                {
                                  "encouragementToReplace": { "text": "Too slow.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
                                  "summaryBulletsToReplace": [
                                    { "text": "- slower fallback", "sourceEventIDs": ["\(newID.uuidString)"] }
                                  ],
                                  "detailBlocksToAppend": [],
                                  "todoItemsToReplace": [
                                    { "text": "- [ ] slower fallback", "sourceEventIDs": ["\(newID.uuidString)"] }
                                  ]
                                }
                                """
                            } catch {
                                await attemptRecorder.recordCancelled(attemptEngine)
                                throw error
                            }
                        default:
                            throw URLError(.cannotConnectToHost)
                        }
                    }
                )
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.engineStatuses[.claudeCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "claude")
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "gemini")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let snapshot = await attemptRecorder.snapshot()
        XCTAssertTrue(snapshot.started.contains(.geminiCLI))
        XCTAssertTrue(snapshot.started.contains(.claudeCLI))
        XCTAssertEqual(snapshot.cancelled, [.claudeCLI])

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Closed strong."))
        XCTAssertTrue(refreshedMarkdown.contains("- Customer approved the follow-up"))
        XCTAssertFalse(refreshedMarkdown.contains("Too slow."))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayIncrementalRejectsReplacementRefsOutsideCurrentDay() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        let outsideDayID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "invalid-ref-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "invalid-ref-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(
                dayKey: dayKey,
                events: try writer.fetchEvents(dayKey: dayKey),
                story: existingStory
            ),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: newID, summaryLine: "Unexpected full refresh"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(outsideDayID.uuidString)"] },
              "summaryBulletsToReplace": [
                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
              ],
              "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ]
            }
            """
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return summarizer
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Keep the old pace."))
        XCTAssertFalse(refreshedMarkdown.contains("Closed strong."))
        XCTAssertNotNil(appState.dayRefreshStatus.lastError)
        let counts = await summarizer.recorder.counts()
        XCTAssertEqual(counts.summarizeIncremental, 1)
    }

    func testRefreshSelectedDayIncrementalDropsDetailRefsOutsideNewEventSet() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        let invalidDetailID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "drop-detail-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "drop-detail-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: """
                            # You did a good job today

                            Keep the old pace.

                            # Summary

                            - Wrapped the first pass

                            # Details

                            ## Existing Thread

                            Closed the first workflow.

                            # To-do

                            - [ ] Send recap
                            """,
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: environment.composer.compose(
                dayKey: dayKey,
                events: try writer.fetchEvents(dayKey: dayKey),
                story: existingStory
            ),
            story: existingStory,
            environment: environment
        )

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let summarizer = RecordingIncrementalSummarizer(
            summarizeResponse: makeValidStoryResponse(sourceEventID: newID, summaryLine: "Unexpected full refresh"),
            summarizeIncrementalResponse: """
            {
              "encouragementToReplace": { "text": "Closed strong.", "sourceEventIDs": ["\(oldID.uuidString)", "\(newID.uuidString)"] },
              "summaryBulletsToReplace": [
                { "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }
              ],
              "detailBlocksToAppend": [
                { "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] },
                { "text": "## Invalid\\n\\nThis should be dropped.", "sourceEventIDs": ["\(invalidDetailID.uuidString)"] }
              ],
              "todoItemsToReplace": [
                { "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }
              ]
            }
            """
        )
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return summarizer
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let refreshedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"))
        XCTAssertTrue(refreshedMarkdown.contains("Closed strong."))
        XCTAssertTrue(refreshedMarkdown.contains("## Follow-up"))
        XCTAssertFalse(refreshedMarkdown.contains("## Invalid"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayIncrementalFailurePreservesExistingFiles() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let oldID = UUID()
        let newID = UUID()
        try writer.insert(
            EventRecord(
                id: oldID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Wrapped the first pass",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "preserve-old"
            )
        )
        try writer.insert(
            EventRecord(
                id: newID,
                sourceType: .notification,
                sourceApp: "Mail",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 11).date!,
                dayKey: dayKey,
                text: "Customer approved the follow-up",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "preserve-new"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# You did a good job today\n\nKeep the pace.\n\n# Summary\n\n- Wrapped the first pass\n\n# Details\n\n## Existing Thread\n\nClosed the first workflow.\n\n# To-do\n\n- [ ] Send recap",
                            sourceEventIDs: [oldID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(dayKey: dayKey, events: try writer.fetchEvents(dayKey: dayKey), story: existingStory)
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                guard engine == .codexCLI else { return nil }
                return StaticSummarizer(response: "not json")
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        XCTAssertEqual(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")), originalMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertNotNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayFullRecoveryChunksTodayAndOverwritesExistingModelStory() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = "2026-04-11"
        let writer = try DatabaseWriter.inMemory()

        for index in 0..<205 {
            try writer.insert(
                EventRecord(
                    id: UUID(),
                    sourceType: .clipboard,
                    sourceApp: "Notes",
                    capturedAt: now.addingTimeInterval(TimeInterval(index)),
                    dayKey: dayKey,
                    text: "today-full-refresh \(index)",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "today-full-refresh-\(index)"
                )
            )
        }

        let supportURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let vaultURL = supportURL.appending(path: "Vault", directoryHint: .isDirectory)
        let summarizer = RecordingOnboardingBootstrapSummarizer()
        let environment = AppEnvironment(
            databaseURL: supportURL.appending(path: "events.sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )

        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# Existing\n\nKeep the existing story for overwrite coverage.",
                            sourceEventIDs: []
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 0
            )
        )
        let originalMarkdown = environment.composer.compose(
            dayKey: dayKey,
            events: try writer.fetchEvents(dayKey: dayKey),
            story: existingStory
        )
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)

        let recorder = RefreshStageRecorder()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            onRefreshStageChange: recorder.record,
            currentDate: { now }
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDayFullRecovery(now: now)

        let preparingJob = try XCTUnwrap(recorder.jobs.first(where: { $0.stage == .preparingStory }))
        XCTAssertTrue(recorder.stages.contains(.loadingEvents))
        XCTAssertTrue(preparingJob.completedStages.contains(.loadingEvents))

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(
            invocations.map(\.kind),
            [.fullRecovery, .incrementalAppend, .incrementalAppend, .incrementalAppend, .incrementalAppend]
        )
        XCTAssertEqual(invocations.map { $0.eventIDs.count }, [50, 50, 50, 50, 5])
        XCTAssertTrue(invocations.allSatisfy { $0.eventIDs.count <= 50 })

        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        XCTAssertEqual(environment.composer.usedSourceEventIDs(in: persistedStory).count, 205)

        let logFiles = try FileManager.default.contentsOfDirectory(
            at: environment.refreshLogsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let logURL = try XCTUnwrap(logFiles.first(where: { $0.lastPathComponent.contains("__\(dayKey)__") }))
        let logContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("\"mode\" : \"fullRecovery\""))
        XCTAssertTrue(logContents.contains("Chunked full refresh into 5 batch(es)"))
    }

    func testRefreshSelectedDayIncrementalChunksLargeManualUpdate() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = "2026-04-11"
        let writer = try DatabaseWriter.inMemory()
        let existingEventID = UUID()
        try writer.insert(
            EventRecord(
                id: existingEventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-1),
                dayKey: dayKey,
                text: "existing event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "existing-event"
            )
        )
        for index in 0..<133 {
            try writer.insert(
                EventRecord(
                    id: UUID(),
                    sourceType: .clipboard,
                    sourceApp: "Notes",
                    capturedAt: now.addingTimeInterval(TimeInterval(index)),
                    dayKey: dayKey,
                    text: "manual-incremental-chunk \(index)",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "manual-incremental-chunk-\(index)"
                )
            )
        }

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: now,
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nAlready written.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Existing summary.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "# Details\n\n## Existing\n\nAlready written.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Existing task",
                            sourceEventIDs: [existingEventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(
            dayKey: dayKey,
            events: try writer.fetchEvents(dayKey: dayKey),
            story: existingStory
        )
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)
        let appState = AppState(environment: environment, bootstrapServices: false, currentDate: { now })
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: now)

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(invocations.map(\.kind), [.incrementalAppend, .incrementalAppend, .incrementalAppend])
        XCTAssertEqual(invocations.map { $0.eventIDs.count }, [50, 50, 33])
        XCTAssertTrue(invocations.allSatisfy { $0.eventIDs.count <= 50 })

        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        XCTAssertEqual(environment.composer.usedSourceEventIDs(in: persistedStory).count, 134)

        let refreshLogs = try FileManager.default.contentsOfDirectory(
            at: environment.refreshLogsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let logURL = try XCTUnwrap(
            refreshLogs
                .filter { $0.lastPathComponent.contains("__\(dayKey)__") }
                .max(by: {
                    let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return leftDate < rightDate
                })
        )
        let logContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("Chunked incremental update into 3 batch(es)"), logContents)
        XCTAssertTrue(logContents.contains("chunk 1\\/3 loaded 50 event(s)"), logContents)
        XCTAssertTrue(logContents.contains("50\\/133 new event(s) appended"), logContents)
    }

    func testRefreshSelectedDayIncrementalKeepsPartialStoryWhenLaterChunkFails() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = "2026-04-11"
        let writer = try DatabaseWriter.inMemory()
        let existingEventID = UUID()
        try writer.insert(
            EventRecord(
                id: existingEventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-1),
                dayKey: dayKey,
                text: "existing event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "existing-partial-event"
            )
        )
        for index in 0..<133 {
            try writer.insert(
                EventRecord(
                    id: UUID(),
                    sourceType: .clipboard,
                    sourceApp: "Notes",
                    capturedAt: now.addingTimeInterval(TimeInterval(index)),
                    dayKey: dayKey,
                    text: "manual-incremental-partial \(index)",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "manual-incremental-partial-\(index)"
                )
            )
        }

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        summarizer.failingIncrementalChunkByDay = [dayKey: 2]
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: now,
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-encouragement",
                            text: "# You did a good job today\n\nAlready written.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-summary",
                            text: "# Summary\n\n- Existing summary.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-details-0",
                            text: "# Details\n\n## Existing\n\nAlready written.",
                            sourceEventIDs: [existingEventID]
                        ),
                        DailyStoryParagraph(
                            id: "daily-journal-todo",
                            text: "# To-do\n\n- [ ] Existing task",
                            sourceEventIDs: [existingEventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(
            dayKey: dayKey,
            events: try writer.fetchEvents(dayKey: dayKey),
            story: existingStory
        )
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)
        let appState = AppState(environment: environment, bootstrapServices: false, currentDate: { now })
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: now)

        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        XCTAssertEqual(environment.composer.usedSourceEventIDs(in: persistedStory).count, 51)
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .failed)
        XCTAssertTrue(appState.dayRefreshStatus.lastError?.contains("chunk 2/3") == true)

        let refreshLogs = try FileManager.default.contentsOfDirectory(
            at: environment.refreshLogsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let logURL = try XCTUnwrap(
            refreshLogs
                .filter { $0.lastPathComponent.contains("__\(dayKey)__") }
                .max(by: {
                    let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return leftDate < rightDate
                })
        )
        let logContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("Incremental update failed during chunk 2\\/3"), logContents)
    }

    func testRefreshSelectedDayFullRecoveryAlsoRunsForHistoricalSelectedDay() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let dayKey = "2026-04-10"
        let writer = try DatabaseWriter.inMemory()
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-86_400),
                dayKey: dayKey,
                text: "yesterday should not full refresh from the today menu",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "yesterday-force-refresh-guard"
            )
        )

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now }
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDayFullRecovery(now: now)

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(invocations.map(\.kind), [.fullRecovery])
        XCTAssertEqual(invocations.first?.dayKey, dayKey)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey)?.dayKey, dayKey)
    }

    func testRefreshSelectedDayFallsBackToParallelGreenEnginesAfterDefaultFailureAndCancelsLosers() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-09"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 9, hour: 9).date!,
                dayKey: dayKey,
                text: "Recover this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "retry-day"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: "{}"),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let attemptRecorder = ParallelAttemptRecorder()

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            summarizerConfig: config,
            makeSummarizer: { engine, _, _ in
                let attemptEngine = engine
                return HandlerSummarizer { dayKey, _, _ in
                    await attemptRecorder.recordStart(attemptEngine)
                    switch attemptEngine {
                    case .codexCLI:
                        return "not json"
                    case .geminiCLI:
                        await attemptRecorder.waitForGeminiAndClaudeToStart()
                        return """
                        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- \(dayKey) recovered","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
                        """
                    case .claudeCLI:
                        do {
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                            return """
                            {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- slower fallback","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
                            """
                        } catch {
                            await attemptRecorder.recordCancelled(attemptEngine)
                            throw error
                        }
                    default:
                        throw URLError(.cannotConnectToHost)
                    }
                }
            }
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "codex")
        appState.engineStatuses[.claudeCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "claude")
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Ready.", lastVerifiedAt: Date(), configurationSignature: "gemini")
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11).date!)

        let snapshot = await attemptRecorder.snapshot()
        XCTAssertTrue(snapshot.started.contains(.geminiCLI))
        XCTAssertTrue(snapshot.started.contains(.claudeCLI))
        XCTAssertEqual(snapshot.cancelled, [.claudeCLI])
        XCTAssertTrue(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")).contains("2026-04-09 recovered"))
        XCTAssertNil(appState.dayRefreshStatus.lastError)
    }

    func testRefreshSelectedDayFailsInsteadOfFullRecoveryWhenExistingStoryCannotBeLoaded() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-11"
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 10).date!,
                dayKey: dayKey,
                text: "Existing day should not be regenerated if story loading fails",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "invalid-story-load"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let markdownURL = vaultURL.appending(path: "\(dayKey).md")
        try "keep this markdown".write(to: markdownURL, atomically: true, encoding: .utf8)
        let storyURL = vaultURL.appending(path: "\(dayKey).story.json")
        try "{ invalid json".write(to: storyURL, atomically: true, encoding: .utf8)

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Should not be used")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 12).date!)

        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), "keep this markdown")
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .failed)
        XCTAssertTrue(appState.dayRefreshStatus.lastError?.contains("Failed to load existing story") == true)
    }

    func testRefreshSelectedDayFullRecoveryWithoutVerifiedEngineFailsAndPreservesExistingFiles() async throws {
        let writer = try DatabaseWriter.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let dayKey = "2026-04-11"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: DateComponents(calendar: calendar, year: 2026, month: 4, day: 11, hour: 9).date!,
                dayKey: dayKey,
                text: "Recover this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-no-engine"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: calendar)
            )
        )
        let existingStory = DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# Summary\n\n- Existing fallback content",
                            sourceEventIDs: [eventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .fallback,
                engineKind: "codexCLI",
                engineLabel: "Codex (CLI)",
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
        let originalMarkdown = environment.composer.compose(dayKey: dayKey, events: try writer.fetchEvents(dayKey: dayKey), story: existingStory)
        try writeStoryDay(dayKey: dayKey, markdown: originalMarkdown, story: existingStory, environment: environment)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            makeSummarizer: { _, _, _ in nil }
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: DateComponents(calendar: calendar, year: 2026, month: 4, day: 13).date!)

        XCTAssertEqual(try String(contentsOf: vaultURL.appending(path: "\(dayKey).md")), originalMarkdown)
        XCTAssertEqual(try environment.loadDailyStory(dayKey: dayKey), existingStory)
        XCTAssertEqual(appState.refreshJob(for: dayKey)?.stage, .failed)
        XCTAssertEqual(appState.dayRefreshStatus.lastError, "Configure and verify an engine to generate this journal")
    }

    func testRefreshSelectedDayPublishesVisibleStages() async throws {
        let writer = try DatabaseWriter.inMemory()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 10).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now,
                dayKey: "2026-04-09",
                text: "Refresh this day",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-visible-stages"
            )
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Visible stages")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let recorder = RefreshStageRecorder()
        let appState = AppState(
            environment: environment,
            onRefreshStageChange: recorder.record
        )
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(
            recorder.stages,
            [.syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles, .completed]
        )
    }

    func testRefreshSelectedDayRejectsDuplicateInFlightRefreshForSameDay() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-09")
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!

        let first = Task {
            await appState.refreshSelectedDay(now: now)
        }

        await gate.waitUntilStarted(dayKey: "2026-04-09")
        let second = Task {
            await appState.refreshSelectedDay(now: now)
        }

        await Task.yield()

        let startCount = await gate.startCount(for: "2026-04-09")
        XCTAssertEqual(startCount, 1)

        await gate.release(dayKey: "2026-04-09")
        _ = await (first.value, second.value)
    }

    func testRefreshDifferentDaysCanRunConcurrently() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let appState = AppState(environment: environment)
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!

        async let refreshNine: Void = appState.refreshDay("2026-04-09", now: now, environment: environment)
        async let refreshTen: Void = appState.refreshDay("2026-04-10", now: now, environment: environment)

        let bothStarted = await waitUntilAsync(timeoutNanoseconds: 2_000_000_000) {
            let startCountNine = await gate.startCount(for: "2026-04-09")
            let startCountTen = await gate.startCount(for: "2026-04-10")
            return startCountNine > 0 && startCountTen > 0
        }
        XCTAssertTrue(bothStarted, "Expected both refresh jobs to start within the timeout")

        let startCountNine = await gate.startCount(for: "2026-04-09")
        let startCountTen = await gate.startCount(for: "2026-04-10")
        XCTAssertEqual(startCountNine, 1)
        XCTAssertEqual(startCountTen, 1)
        XCTAssertEqual(appState.refreshJob(for: "2026-04-09")?.stage, .generatingStory)
        XCTAssertEqual(appState.refreshJob(for: "2026-04-10")?.stage, .generatingStory)

        await gate.release(dayKey: "2026-04-09")
        await gate.release(dayKey: "2026-04-10")
        _ = await (refreshNine, refreshTen)
    }

    func testCompletingOnboardingStartsTodayThenYesterdayBootstrapSerially() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        await gate.waitUntilStarted(dayKey: "2026-04-11")
        await Task.yield()

        let todayStartedBeforeRelease = await gate.startCount(for: "2026-04-11")
        let yesterdayStartedBeforeRelease = await gate.startCount(for: "2026-04-10")
        XCTAssertEqual(todayStartedBeforeRelease, 1)
        XCTAssertEqual(yesterdayStartedBeforeRelease, 0, "Expected yesterday to wait until today's refresh finishes")
        XCTAssertEqual(Array(appState.availableDates.prefix(3)), ["2026-04-11", "2026-04-10", OnboardingDemoStory.demoDayKey])
        XCTAssertEqual(appState.onboardingBootstrapNotice?.message, "KnowYou is generating today and yesterday from your local context. Come back 2 minutes later.")

        await gate.release(dayKey: "2026-04-11")
        await gate.waitUntilStarted(dayKey: "2026-04-10")
        let yesterdayStartedAfterRelease = await gate.startCount(for: "2026-04-10")
        XCTAssertEqual(yesterdayStartedAfterRelease, 1)

        await gate.release(dayKey: "2026-04-10")
        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish after both serial refreshes were released")
    }

    func testCompletingOnboardingSkipsBootstrapDaysThatAlreadyExist() async throws {
        let (environment, gate) = try makeBlockingRefreshEnvironment()
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try FileManager.default.createDirectory(at: environment.vaultURL, withIntermediateDirectories: true)
        try "# Existing".write(
            to: environment.vaultURL.appending(path: "2026-04-10.md"),
            atomically: true,
            encoding: .utf8
        )

        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )
        appState.refreshNotesIndex()

        appState.completeOnboarding()
        await gate.waitUntilStarted(dayKey: "2026-04-11")
        await Task.yield()

        let todayStarted = await gate.startCount(for: "2026-04-11")
        let yesterdayStarted = await gate.startCount(for: "2026-04-10")
        XCTAssertEqual(todayStarted, 1)
        XCTAssertEqual(yesterdayStarted, 0)

        await gate.release(dayKey: "2026-04-11")
        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish after refreshing the missing day")
    }

    func testCompletingOnboardingSendsCompletionNotificationAfterBootstrapSucceeds() async throws {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let writer = try DatabaseWriter.inMemory()
        let todayID = UUID()
        let yesterdayID = UUID()
        try writer.insert(
            EventRecord(
                id: todayID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: now,
                dayKey: "2026-04-11",
                text: "Wrapped the onboarding polish.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "onboarding-bootstrap-notification-today"
            )
        )
        try writer.insert(
            EventRecord(
                id: yesterdayID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-86_400),
                dayKey: "2026-04-10",
                text: "Outlined the onboarding journey.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "onboarding-bootstrap-notification-yesterday"
            )
        )
        let summarizer = HandlerIncrementalSummarizer(
            summarizeHandler: { dayKey, _, _ in
                let sourceID = switch dayKey {
                case "2026-04-11": todayID
                case "2026-04-10": yesterdayID
                default: UUID()
                }
                return """
                {
                  "sections": [{
                    "id": "daily-journal",
                    "paragraphs": [{
                      "text": "# Details\\n\\n## \(dayKey)\\n\\nClosed the onboarding bootstrap loop.",
                      "sourceEventIDs": ["\(sourceID.uuidString)"]
                    }]
                  }]
                }
                """
            },
            summarizeIncrementalHandler: { _, _, _ in
                XCTFail("Incremental summarize should not be used for onboarding bootstrap")
                return ""
            }
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notifiedDayKeys = ThreadSafeDayKeyCapture()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            notifyOnboardingBootstrapCompletion: { dayKeys in
                notifiedDayKeys.setValue(dayKeys)
            },
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish after both successful serial refreshes")
        XCTAssertEqual(notifiedDayKeys.value.sorted(by: >), ["2026-04-11", "2026-04-10"])
    }

    func testCompletingOnboardingContinuesToYesterdayAfterTodayFails() async throws {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let writer = try DatabaseWriter.inMemory()
        let yesterdayID = UUID()
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: now,
                dayKey: "2026-04-11",
                text: "Today's note should fail.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "onboarding-bootstrap-failure-today"
            )
        )
        try writer.insert(
            EventRecord(
                id: yesterdayID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-86_400),
                dayKey: "2026-04-10",
                text: "Yesterday should still succeed.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "onboarding-bootstrap-failure-yesterday"
            )
        )

        let summarizer = HandlerSummarizer { dayKey, _, _ in
            if dayKey == "2026-04-11" {
                throw URLError(.cannotConnectToHost)
            }

            return """
            {
                  "sections": [{
                    "id": "daily-journal",
                    "paragraphs": [{
                      "text": "# Details\\n\\nRecovered \(dayKey).",
                      "sourceEventIDs": ["\(yesterdayID.uuidString)"]
                    }]
                  }]
                }
            """
        }
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish even when today's generation fails")
        XCTAssertNil(appState.noteIndex["2026-04-11"])
        XCTAssertNotNil(appState.noteIndex["2026-04-10"], "Expected onboarding bootstrap to keep going and generate yesterday")
    }

    func testCompletingOnboardingChunksBootstrapDaysAboveFiftyEvents() async throws {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let writer = try DatabaseWriter.inMemory()
        func insertEvents(count: Int, dayKey: String, baseDate: Date, contentPrefix: String) throws {
            for index in 0..<count {
                try writer.insert(
                    EventRecord(
                        id: UUID(),
                        sourceType: .clipboard,
                        sourceApp: "Notes",
                        capturedAt: baseDate.addingTimeInterval(TimeInterval(index)),
                        dayKey: dayKey,
                        text: "\(contentPrefix) \(index)",
                        auditText: nil,
                        privacyAction: .keep,
                        contentHash: "\(contentPrefix)-\(index)"
                    )
                )
            }
        }
        try insertEvents(count: 205, dayKey: "2026-04-11", baseDate: now, contentPrefix: "today-chunk")
        try insertEvents(count: 120, dayKey: "2026-04-10", baseDate: now.addingTimeInterval(-86_400), contentPrefix: "yesterday-chunk")

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notifiedDayKeys = ThreadSafeDayKeyCapture()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            notifyOnboardingBootstrapCompletion: { dayKeys in
                notifiedDayKeys.setValue(dayKeys)
            },
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish after chunked generation")

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(
            invocations.map(\.dayKey),
            [
                "2026-04-11", "2026-04-11", "2026-04-11", "2026-04-11", "2026-04-11",
                "2026-04-10", "2026-04-10", "2026-04-10"
            ]
        )
        XCTAssertEqual(
            invocations.map(\.kind),
            [
                .fullRecovery, .incrementalAppend, .incrementalAppend, .incrementalAppend, .incrementalAppend,
                .fullRecovery, .incrementalAppend, .incrementalAppend
            ]
        )
        XCTAssertEqual(invocations.map { $0.eventIDs.count }, [50, 50, 50, 50, 5, 50, 50, 20])
        XCTAssertTrue(invocations.allSatisfy { $0.eventIDs.count <= 50 })
        XCTAssertEqual(notifiedDayKeys.value.sorted(by: >), ["2026-04-11", "2026-04-10"])

        let refreshLogs = try FileManager.default.contentsOfDirectory(
            at: environment.refreshLogsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let todayLogURL = try XCTUnwrap(
            refreshLogs
                .filter { $0.lastPathComponent.contains("__2026-04-11__") }
                .max(by: {
                    let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return leftDate < rightDate
                })
        )
        let todayLog = try String(contentsOf: todayLogURL, encoding: .utf8)
        XCTAssertTrue(todayLog.contains("Chunked onboarding bootstrap into 5 batch(es)"))
        XCTAssertTrue(todayLog.contains("chunk 1\\/5 loaded 50 event(s); 50\\/205 cumulative"))
    }

    func testCompletingOnboardingKeepsPartialStoryWhenLaterChunkFailsAndContinuesToYesterday() async throws {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let writer = try DatabaseWriter.inMemory()
        func insertEvents(count: Int, dayKey: String, baseDate: Date, contentPrefix: String) throws {
            for index in 0..<count {
                try writer.insert(
                    EventRecord(
                        id: UUID(),
                        sourceType: .clipboard,
                        sourceApp: "Notes",
                        capturedAt: baseDate.addingTimeInterval(TimeInterval(index)),
                        dayKey: dayKey,
                        text: "\(contentPrefix) \(index)",
                        auditText: nil,
                        privacyAction: .keep,
                        contentHash: "\(contentPrefix)-\(index)"
                    )
                )
            }
        }
        try insertEvents(count: 150, dayKey: "2026-04-11", baseDate: now, contentPrefix: "today-partial")
        try insertEvents(count: 2, dayKey: "2026-04-10", baseDate: now.addingTimeInterval(-86_400), contentPrefix: "yesterday-success")

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        summarizer.failingIncrementalChunkByDay = ["2026-04-11": 1]
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notifiedDayKeys = ThreadSafeDayKeyCapture()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            notifyOnboardingBootstrapCompletion: { dayKeys in
                notifiedDayKeys.setValue(dayKeys)
            },
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish even when a later chunk fails")
        XCTAssertNotNil(appState.noteIndex["2026-04-11"], "Expected the first chunk to leave a partial story behind")
        XCTAssertNotNil(appState.noteIndex["2026-04-10"], "Expected onboarding bootstrap to continue to yesterday")
        XCTAssertEqual(notifiedDayKeys.value, [])

        let partialStory = try XCTUnwrap(environment.loadDailyStory(dayKey: "2026-04-11"))
        XCTAssertEqual(environment.composer.usedSourceEventIDs(in: partialStory).count, 50)

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(invocations.map(\.dayKey), ["2026-04-11", "2026-04-11", "2026-04-10"])
        XCTAssertEqual(invocations.map(\.kind), [.fullRecovery, .incrementalAppend, .fullRecovery])
    }

    func testCompletingOnboardingDoesNotChunkDaysAtFiftyEventsOrFewer() async throws {
        let now = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11, hour: 15, minute: 30).date!
        let writer = try DatabaseWriter.inMemory()
        for index in 0..<50 {
            try writer.insert(
                EventRecord(
                    id: UUID(),
                    sourceType: .clipboard,
                    sourceApp: "Notes",
                    capturedAt: now.addingTimeInterval(TimeInterval(index)),
                    dayKey: "2026-04-11",
                    text: "exact-threshold \(index)",
                    auditText: nil,
                    privacyAction: .keep,
                    contentHash: "exact-threshold-\(index)"
                )
            )
        }
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: now.addingTimeInterval(-86_400),
                dayKey: "2026-04-10",
                text: "small yesterday",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "small-yesterday"
            )
        )

        let summarizer = RecordingOnboardingBootstrapSummarizer()
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            currentDate: { now },
            userDefaults: defaults,
            keychainService: "MainWindowViewModelTests"
        )

        appState.completeOnboarding()

        let completed = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            appState.onboardingBootstrapState == .complete
        }
        XCTAssertTrue(completed, "Expected onboarding bootstrap to finish without chunking at the threshold")

        let invocations = await summarizer.recorder.snapshot()
        XCTAssertEqual(invocations.map(\.kind), [.fullRecovery, .fullRecovery])
        XCTAssertEqual(invocations.first?.eventIDs.count, 50)
        XCTAssertFalse(invocations.contains(where: { $0.kind == .incrementalAppend }))
    }

    func testRefreshSelectedDayFor20260409CompletesWithVisibleTerminalState() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 9, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-09",
                text: "Regression refresh event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-2026-04-09-terminal"
            )
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Terminal state complete")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment)
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(appState.refreshJob(for: "2026-04-09")?.stage, .completed)
    }

    func testRefreshSelectedDayTracksCompletedStagesAndTerminalSummary() async throws {
        let writer = try DatabaseWriter.inMemory()
        let capturedAt = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 9, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: UUID(),
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: "2026-04-09",
                text: "Regression refresh event",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "refresh-2026-04-09-summary"
            )
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: StaticSummarizer(response: makeValidStoryResponse(summaryLine: "Terminal summary complete")),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        let appState = AppState(environment: environment, summarizerConfig: config)
        appState.selectDate("2026-04-09")

        await appState.refreshSelectedDay(
            now: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 11).date!
        )

        XCTAssertEqual(
            appState.refreshJob(for: "2026-04-09")?.completedStages,
            [.syncingNotifications, .loadingEvents, .preparingStory, .generatingStory, .writingFiles]
        )
        XCTAssertEqual(
            appState.refreshJob(for: "2026-04-09")?.summary,
            "Completed · Codex (CLI) returned successfully"
        )
    }

    func testRefreshServiceStatusesPreservesSummarizerRuntimeHistory() {
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let completedAt = Date(timeIntervalSince1970: 1_775_000_000)
        appState.summarizerStatus = SummarizerRuntimeStatus(
            mode: "OpenAI API",
            isConfigured: true,
            lastCompletedAt: completedAt,
            lastError: "timed out"
        )

        appState.refreshServiceStatuses()

        XCTAssertEqual(appState.summarizerStatus.lastCompletedAt, completedAt)
        XCTAssertEqual(appState.summarizerStatus.lastError, "timed out")
    }

    func testSummarizerStatusInfersFailureKindFromActiveEngineDetail() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .yellow,
            detail: "Structured repair failed: repair output was not valid structured JSON",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_100_000),
            configurationSignature: "codex|\(executableURL.path)"
        )

        XCTAssertEqual(appState.summarizerStatus.failureKind, .repairFailed)
    }

    func testRefreshEngineStatusesPreservesLastVerifiedStateForUnchangedEngine() {
        let executableURL = try! makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_100_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt
        )

        appState.refreshEngineStatuses()

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Smoke test succeeded.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)
    }

    func testAppStateExposesDefaultEngineAndStatusesForSelectorUI() {
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_150_000),
            configurationSignature: "codex|/tmp/codex"
        )
        appState.engineStatuses[.openAI] = EngineRuntimeStatus(
            state: .yellow,
            detail: "API configuration changed. Retest required.",
            lastVerifiedAt: nil,
            configurationSignature: "https://api.openai.com/v1/responses|gpt-5|"
        )

        XCTAssertEqual(appState.defaultEngine.displayName, "Codex (CLI)")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)
    }

    func testApplyEngineConfigKeepsGreenDefaultActiveWhenNewEngineProbeFails() async throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var initialConfig = SummarizerConfig.default
        initialConfig.defaultEngine = .codexCLI
        initialConfig.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: initialConfig,
            probeEngine: { engine, _, _ in
                EngineProbeResult(
                    engine: engine,
                    state: .yellow,
                    detail: "API request failed.",
                    verifiedAt: Date(timeIntervalSince1970: 1_775_200_000)
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_190_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        var editedConfig = initialConfig
        editedConfig.defaultEngine = .openAI
        editedConfig.apiBaseURL = "https://example.com/v1/responses"
        editedConfig.apiModel = "gpt-5"
        editedConfig.apiToken = "token-test-123"

        appState.applyEngineConfig(editedConfig)
        await appState.retestEngine(.openAI)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)

        let activeSummarizer = try XCTUnwrap(appState.environment?.summarizer as? CLISummarizer)
        XCTAssertEqual(activeSummarizer.tool, .codex)
        XCTAssertEqual(activeSummarizer.executablePath, executableURL.path)

        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testApplySummarizerConfigPersistsRequestedYellowEngineAsDefaultChoice() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.applySummarizerConfig(config)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        let activeSummarizer = try XCTUnwrap(appState.environment?.summarizer as? CLISummarizer)
        XCTAssertEqual(activeSummarizer.tool, .codex)
        XCTAssertEqual(activeSummarizer.executablePath, executableURL.path)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")

        let persistedConfig = SummarizerConfig.load(
            from: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        XCTAssertEqual(persistedConfig.defaultEngine, .codexCLI)
        XCTAssertEqual(persistedConfig.codexCLIPath, executableURL.path)
    }

    func testApplySummarizerConfigAllowsLegacyDisableException() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var activeConfig = SummarizerConfig.default
        activeConfig.defaultEngine = .codexCLI
        activeConfig.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: activeConfig,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_205_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        var disabledConfig = activeConfig
        disabledConfig.defaultEngine = .none
        appState.applySummarizerConfig(disabledConfig)

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.none.displayName)
        XCTAssertNil(appState.environment?.summarizer)

        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testYellowEngineCanBecomeDefaultChoiceWithoutBlockingGreenSelection() {
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-5"
        config.apiToken = "token-test-123"

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.applyEngineConfig(config)
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(state: .yellow, detail: "Smoke test failed.", lastVerifiedAt: nil)
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(state: .green, detail: "Smoke test succeeded.", lastVerifiedAt: nil)

        appState.selectDefaultEngine(.codexCLI)
        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )

        appState.selectDefaultEngine(.geminiCLI)
        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .geminiCLI
        )
    }

    func testSelectingNoneDisablesActiveSummarizerAndPersistsNoneAsDefault() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_400_000),
            configurationSignature: "codex|\(executableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        XCTAssertNotNil(appState.environment?.summarizer)

        appState.selectDefaultEngine(.none)

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testEditingAPIConfigReturnsAPIRowToYellowUntilRetested() async throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .openAI
        config.apiBaseURL = "https://example.com/v1/responses"
        config.apiModel = "gpt-5"
        config.apiToken = "token-test-123"
        config.codexCLIPath = executableURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_300_000)
        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.openAI] = EngineRuntimeStatus(
            state: .green,
            detail: "API returned an expected acknowledgement.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "https://example.com/v1/responses|gpt-5|token-test-123"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(executableURL.path)"
        )

        config.apiModel = "gpt-5-mini"
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.engineStatuses[.openAI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.openAI]?.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)

        let summarizer = try XCTUnwrap(appState.environment?.summarizer as? CloudSummarizer)
        XCTAssertEqual(summarizer.model, "gpt-5-mini")
    }

    func testRetestEngineDiscardsStaleProbeResultWhenConfigChangesMidFlight() async throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")
        let verifiedAt = Date(timeIntervalSince1970: 1_775_310_000)
        let probeGate = ProbeGate()

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                await probeGate.markStarted()
                await probeGate.waitForRelease()
                return EngineProbeResult(
                    engine: engine,
                    state: .green,
                    detail: "Smoke test succeeded.",
                    verifiedAt: verifiedAt
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let retestTask = Task {
            await appState.retestEngine(.codexCLI)
        }

        await probeGate.waitUntilStarted()

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")

        await probeGate.release()
        await retestTask.value

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, nil)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(updatedExecutableURL.path)")
    }

    func testRetestAllEnginesStartsProbesInParallel() async {
        let codexGate = ProbeGate()
        let tracker = ProbeStartTracker()

        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                await tracker.markStarted(engine)
                if engine == .codexCLI {
                    await codexGate.markStarted()
                    await codexGate.waitForRelease()
                }
                return EngineProbeResult(
                    engine: engine,
                    state: .green,
                    detail: "Smoke test succeeded.",
                    verifiedAt: Date(timeIntervalSince1970: 1_775_310_000)
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let retestTask = Task {
            await appState.retestAllEngines()
        }

        await codexGate.waitUntilStarted()
        await tracker.waitUntilStarted([.codexCLI, .geminiCLI])

        XCTAssertTrue(appState.isRetestingEngines)
        XCTAssertTrue(appState.retestingEngines.contains(.codexCLI))

        await codexGate.release()
        await retestTask.value

        XCTAssertFalse(appState.isRetestingEngines)
        XCTAssertTrue(appState.retestingEngines.isEmpty)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.geminiCLI]?.state, .green)
    }

    func testRetestAllEnginesAutoSelectsHighestPriorityGreenEngineWhenDefaultIsNone() async {
        let verifiedAt = Date(timeIntervalSince1970: 1_775_350_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: .default,
            probeEngine: { engine, _, _ in
                switch engine {
                case .codexCLI, .geminiCLI:
                    return EngineProbeResult(
                        engine: engine,
                        state: .green,
                        detail: "Smoke test succeeded.",
                        verifiedAt: verifiedAt
                    )
                default:
                    return EngineProbeResult(
                        engine: engine,
                        state: .gray,
                        detail: "Executable not found.",
                        verifiedAt: nil
                    )
                }
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testRetestAllEnginesDoesNotOverrideExplicitDefaultEngine() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        let geminiURL = try makeStubExecutable(named: "gemini")
        var config = SummarizerConfig.default
        config.defaultEngine = .geminiCLI
        config.codexCLIPath = codexURL.path
        config.geminiCLIPath = geminiURL.path
        let verifiedAt = Date(timeIntervalSince1970: 1_775_360_000)

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = switch engine {
                case .codexCLI, .geminiCLI:
                    .green
                default:
                    .gray
                }
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(appState.engineStatuses[.geminiCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
    }

    func testExplicitlyDisabledEngineStaysNoneAcrossRefreshAndRetestReconciliation() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.codexCLIPath = codexURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_370_000)
        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(codexURL.path)"
        )

        appState.selectDefaultEngine(.codexCLI)
        appState.selectDefaultEngine(.none)
        appState.refreshEngineStatuses()

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
    }

    func testLoadedDefaultNoneAutoPicksVerifiedEngineWhenSuppressionWasNeverSaved() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .none
        config.codexCLIPath = codexURL.path
        config.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.removeObject(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)

        let verifiedAt = Date(timeIntervalSince1970: 1_775_380_000)
        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)
        )

        await appState.retestAllEngines()

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
        XCTAssertEqual(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection) as? Bool,
            false
        )
    }

    func testLoadedDefaultNoneRemainsEligibleForAutoPickWhenSuppressionWasNeverSaved() async throws {
        let codexURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .none
        config.codexCLIPath = codexURL.path
        config.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let verifiedAt = Date(timeIntervalSince1970: 1_775_381_000)
        let appState = AppState(
            bootstrapServices: false,
            probeEngine: { engine, _, _ in
                let state: EngineIndicatorState = engine == .codexCLI ? .green : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection)
        )

        await appState.retestEngine(.codexCLI)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
        XCTAssertEqual(
            engineDefaults.object(forKey: AppState.UserDefaultsKeys.explicitlyDisabledSummarizerAutoSelection) as? Bool,
            false
        )
    }

    func testRetestRebuildsActiveSummarizerWhenCurrentDefaultTurnsGreen() async throws {
        let executableDirectory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: executableDirectory) }
        let codexURL = executableDirectory.appending(path: "codex")
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }
        var initialConfig = SummarizerConfig.default
        initialConfig.defaultEngine = .codexCLI
        initialConfig.codexCLIPath = codexURL.path

        let verifiedAt = Date(timeIntervalSince1970: 1_775_382_000)
        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: initialConfig,
            probeEngine: { engine, config, _ in
                let state: EngineIndicatorState = engine == .codexCLI &&
                    FileManager.default.isExecutableFile(atPath: config.codexCLIPath)
                    ? .green
                    : .gray
                return EngineProbeResult(
                    engine: engine,
                    state: state,
                    detail: state == .green ? "Smoke test succeeded." : "Executable not found.",
                    verifiedAt: state == .green ? verifiedAt : nil
                )
            },
            processEnvironment: processEnvironment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertNil(appState.environment?.summarizer)

        try "#!/bin/sh\nexit 0\n".write(to: codexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codexURL.path)

        await appState.retestEngine(.codexCLI)

        let activeSummarizer = try XCTUnwrap(appState.environment?.summarizer as? CLISummarizer)
        XCTAssertEqual(activeSummarizer.tool, .codex)
        XCTAssertEqual(activeSummarizer.executablePath, codexURL.path)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
    }

    func testGenerateStoryFallsBackWithoutEngineAndAnnotatesFallbackProvenance() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-11"
        let eventID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_775_600_000)
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: capturedAt,
                dayKey: dayKey,
                text: "Closed the loop on the shipping checklist",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "fallback-provenance"
            )
        )

        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertFalse(story.sections.flatMap(\.paragraphs).isEmpty)
        XCTAssertEqual(story.provenance?.generationMode, .fallback)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.none.rawValue)
        XCTAssertEqual(story.provenance?.engineLabel, DiaryEngine.none.displayName)
        XCTAssertEqual(story.provenance?.curatedEventCount, 1)
    }

    func testGenerateStoryAnnotatesModelProvenanceWhenSummarizerSucceeds() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-11"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_600_500),
                dayKey: dayKey,
                text: "Summarized a clean planning thread",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "model-provenance"
            )
        )

        let response = """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- Summarized a clean planning thread","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
        """
        let executableURL = try makeStubExecutable(named: "codex")
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        environment.summarizer = StaticSummarizer(response: response)
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertEqual(story.provenance?.generationMode, .model)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.codexCLI.rawValue)
        XCTAssertEqual(story.provenance?.engineLabel, DiaryEngine.codexCLI.displayName)
        XCTAssertEqual(story.provenance?.curatedEventCount, 1)
    }

    func testGenerateStoryIgnoresLegacyPromptOverrideInPersistedConfig() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-12"
        let eventID = UUID()
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .clipboard,
                sourceApp: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_000),
                dayKey: dayKey,
                text: "Captured a real prompt integration test",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-integration"
            )
        )

        let response = """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- Captured a real prompt integration test","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
        """
        var storedConfig = SummarizerConfig.default
        storedConfig.defaultEngine = .none
        storedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.set("Custom live global diary prompt override", forKey: "summarizerGlobalDiaryPromptOverride")
        let summarizer = RecordingPromptSummarizer(response: response)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let events = try writer.fetchEvents(dayKey: dayKey)

        let story = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertEqual(summarizer.capturedDayKey, dayKey)
        XCTAssertEqual(
            summarizer.capturedMarkdown,
            environment.composer.storyPrompt(dayKey: dayKey, events: events)
        )
        XCTAssertEqual(story.provenance?.generationMode, .model)
        XCTAssertEqual(story.provenance?.engineKind, DiaryEngine.none.rawValue)
        XCTAssertNil(engineDefaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
    }

    func testGenerateStoryPromptTruncatesLongEventTextBeforeSummarizerCall() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-21"
        let eventID = UUID()
        let longText = String(repeating: "C", count: 160)
        let expectedText = String(repeating: "C", count: 100)
        try writer.insert(
            EventRecord(
                id: eventID,
                sourceType: .notification,
                sourceApp: "com.openai.codex",
                capturedAt: Date(timeIntervalSince1970: 1_776_729_600),
                dayKey: dayKey,
                text: longText,
                auditText: nil,
                privacyAction: .keep,
                contentHash: "prompt-budget-integration"
            )
        )

        let response = """
        {"sections":[{"id":"daily-journal","paragraphs":[{"text":"# Summary\\n- Trimmed the prompt budget","sourceEventIDs":["\(eventID.uuidString)"]}]}]}
        """
        let summarizer = RecordingPromptSummarizer(response: response)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let events = try writer.fetchEvents(dayKey: dayKey)

        _ = await appState.generateStory(dayKey: dayKey, events: events, environment: environment)

        XCTAssertEqual(summarizer.capturedMarkdown, environment.composer.storyPrompt(dayKey: dayKey, events: events))
        XCTAssertTrue(summarizer.capturedMarkdown?.contains("text: \(expectedText)") == true)
        XCTAssertFalse(summarizer.capturedMarkdown?.contains("text: \(longText)") == true)
    }

    func testRefreshSelectedDayFullRecoveryIgnoresLegacyPromptOverrideAndNormalizesBeforePersisting() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-12"
        let firstID = UUID()
        let secondID = UUID()
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_000),
                dayKey: dayKey,
                text: "Adjusted the onboarding preview spacing",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-override-1"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: Date(timeIntervalSince1970: 1_775_700_300),
                dayKey: dayKey,
                text: "Ran the verification build",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "full-recovery-override-2"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let summarizer = RecordingPromptSummarizer(
            response: """
            {
              "sections": [{
                "id": "daily-journal",
                "paragraphs": [{
                  "text": "# Details\\n\\n## Demo polish\\n\\nFigma tightened the preview.\\n\\n## Verification\\n\\nTerminal confirmed the build.",
                  "sourceEventIDs": ["\(firstID.uuidString)", "\(secondID.uuidString)"]
                }]
              }]
            }
            """
        )
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: summarizer,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        var storedConfig = SummarizerConfig.default
        storedConfig.defaultEngine = .none
        storedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        engineDefaults.set("Custom full recovery override", forKey: "summarizerGlobalDiaryPromptOverride")
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.selectDate(dayKey)

        await appState.refreshSelectedDay(now: Date(timeIntervalSince1970: 1_775_800_000))

        let events = try writer.fetchEvents(dayKey: dayKey)
        XCTAssertEqual(
            summarizer.capturedMarkdown,
            environment.composer.storyPrompt(dayKey: dayKey, events: events)
        )
        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        XCTAssertEqual(persistedStory.sections.first?.paragraphs.map(\.id), [
            "daily-journal-0-detail-0",
            "daily-journal-0-detail-1",
        ])
        let markdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("## Demo polish"))
        XCTAssertTrue(markdown.contains("## Verification"))
        XCTAssertNil(engineDefaults.string(forKey: "summarizerGlobalDiaryPromptOverride"))
    }

    func testCompleteOnboardingPersistsVaultAndSelectedVerifiedEngine() throws {
        let executableURL = try makeStubExecutable(named: "gemini")
        var config = SummarizerConfig.default
        config.geminiCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_610_000),
            configurationSignature: "gemini|\(executableURL.path)"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .geminiCLI)

        XCTAssertEqual(appState.defaultEngine, .geminiCLI)
        XCTAssertEqual(environment.vaultURL, vaultURL)
        XCTAssertEqual(engineDefaults.string(forKey: AppState.UserDefaultsKeys.vaultPath), vaultURL.path)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .geminiCLI
        )
        XCTAssertEqual(
            engineDefaults.bool(forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding),
            true
        )
    }

    func testCompleteOnboardingPersistsGraySelectedEngineWithoutBlocking() throws {
        var config = SummarizerConfig.default
        config.defaultEngine = .claudeCLI
        config.claudeCLIPath = "/definitely/missing/claude"
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            processEnvironment: processEnvironment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .claudeCLI)

        XCTAssertEqual(appState.defaultEngine, .claudeCLI)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .claudeCLI
        )
    }

    func testCompleteOnboardingWithNonePreservesExplicitDisableAcrossLaterReconciliation() throws {
        let executableURL = try makeStubExecutable(named: "gemini")
        var config = SummarizerConfig.default
        config.geminiCLIPath = executableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.geminiCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_620_000),
            configurationSignature: "gemini|\(executableURL.path)"
        )
        let vaultURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)

        appState.completeOnboarding(vaultURL: vaultURL, preferredEngine: .none)
        appState.refreshEngineStatuses()

        XCTAssertEqual(appState.defaultEngine, .none)
        XCTAssertNil(appState.environment?.summarizer)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .none
        )
    }

    func testSyncMemoryConfigLoadsFromDefaultsAndPanelStateCanToggle() throws {
        var config = SyncMemoryConfig.default
        config.obsidian.isEnabled = true
        config.obsidian.resolvedPath = "/tmp/\(UUID().uuidString)/obsidian"
        config.autoSyncEnabled = true
        config.save(to: engineDefaults)

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertTrue(appState.syncMemoryConfig.obsidian.isEnabled)
        XCTAssertEqual(appState.syncMemoryConfig.obsidian.resolvedPath, config.obsidian.resolvedPath)
        XCTAssertTrue(appState.syncMemoryConfig.autoSyncEnabled)
        XCTAssertEqual(appState.syncMemoryConfig.dailySyncHour, config.dailySyncHour)
        XCTAssertEqual(appState.syncMemoryConfig.dailySyncMinute, config.dailySyncMinute)
        XCTAssertFalse(appState.isShowingSyncMemoryPanel)

        appState.openSyncMemoryPanel()
        XCTAssertTrue(appState.isShowingSyncMemoryPanel)

        appState.closeSyncMemoryPanel()
        XCTAssertFalse(appState.isShowingSyncMemoryPanel)
    }

    func testSyncMemoryNowCopiesAllDailyNotesToEnabledConfiguredDestinations() throws {
        let environment = try makeEngineEnvironment()
        try FileManager.default.createDirectory(at: environment.vaultURL, withIntermediateDirectories: true)
        try "# Older".write(
            to: environment.vaultURL.appending(path: "2026-04-10.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Latest".write(
            to: environment.vaultURL.appending(path: "2026-04-11.md"),
            atomically: true,
            encoding: .utf8
        )

        let obsidianURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let openClawURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var config = SyncMemoryConfig.default
        config.obsidian.isEnabled = true
        config.obsidian.resolvedPath = obsidianURL.path
        config.openClaw.isEnabled = true
        config.openClaw.resolvedPath = openClawURL.path
        config.save(to: engineDefaults)

        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.syncMemoryNow()

        XCTAssertEqual(
            try String(contentsOf: obsidianURL.appending(path: "2026-04-10.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Older
            """
        )
        XCTAssertEqual(
            try String(contentsOf: obsidianURL.appending(path: "2026-04-11.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Latest
            """
        )
        XCTAssertEqual(
            try String(contentsOf: openClawURL.appending(path: "2026-04-10.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Older
            """
        )
        XCTAssertEqual(
            try String(contentsOf: openClawURL.appending(path: "2026-04-11.md"), encoding: .utf8),
            """
            ---
            knowyou_export: daily_memory
            ---
            # Latest
            """
        )
        XCTAssertEqual(appState.statusMessage, "Synced 2 notes to 2 destinations")
        XCTAssertEqual(appState.syncMemoryStatusMessage, "Synced 2 notes to 2 destinations")
    }

    func testSyncMemoryNowSkipsChannelsWithBlankResolvedPath() throws {
        let environment = try makeEngineEnvironment()
        try FileManager.default.createDirectory(at: environment.vaultURL, withIntermediateDirectories: true)
        try "# Latest".write(
            to: environment.vaultURL.appending(path: "2026-04-12.md"),
            atomically: true,
            encoding: .utf8
        )

        let obsidianURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let openClawURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var config = SyncMemoryConfig.default
        config.obsidian.isEnabled = true
        config.obsidian.resolvedPath = obsidianURL.path
        config.openClaw.isEnabled = true
        config.openClaw.resolvedPath = "   "
        config.save(to: engineDefaults)

        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.syncMemoryNow()

        XCTAssertTrue(FileManager.default.fileExists(atPath: obsidianURL.appending(path: "2026-04-12.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: openClawURL.appending(path: "2026-04-12.md").path))
        XCTAssertEqual(appState.statusMessage, "Synced 1 note to 1 destination")
        XCTAssertEqual(appState.syncMemoryStatusMessage, "Synced 1 note to 1 destination")
    }

    func testImportKnowledgeNowRunsEnabledConnectorsWithoutChangingSyncMemoryExportConfig() async throws {
        let environment = try makeEngineEnvironment()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Imported".write(
            to: root.appending(path: "imported.md"),
            atomically: true,
            encoding: .utf8
        )

        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        var importConfig = KnowledgeImportConfig.default
        importConfig.connectorInstances = [
            KnowledgeConnectorInstanceConfig(
                id: "local-main",
                connectorID: .localFolderImport,
                displayName: "Docs",
                sourcePath: root.path,
                isEnabled: true
            )
        ]
        appState.saveKnowledgeImportConfig(importConfig)

        await appState.importKnowledgeNow()

        XCTAssertEqual(appState.knowledgeImportStatusMessage, "Imported 1 document")
        XCTAssertEqual(appState.statusMessage, "Imported 1 document")
        XCTAssertFalse(appState.syncMemoryConfig.autoSyncEnabled)
    }

    func testSavingSyncMemoryConfigPublishesAutoSyncStatusMessage() {
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests",
            launchAgentManager: LaunchAgentManager(
                fileManager: .default,
                commandRunner: { _ in },
                userIDProvider: { 501 }
            )
        )

        var config = appState.syncMemoryConfig
        config.autoSyncEnabled = true
        config.dailySyncHour = 8
        config.dailySyncMinute = 45

        appState.saveSyncMemoryConfig(config)

        XCTAssertEqual(appState.syncMemoryStatusMessage, "Auto Sync Daily enabled for 08:45")
    }

    func testDailyStoryDecodingBackfillsLegacyProvenanceWhenMissingFromPayload() throws {
        let json = """
        {
          "dayKey": "2026-04-11",
          "generatedAt": 1775600000,
          "sections": [
            {
              "id": "daily-journal",
              "title": "",
              "paragraphs": [
                {
                  "id": "daily-journal-0",
                  "text": "Legacy paragraph",
                  "sourceEventIDs": ["\(UUID().uuidString)"]
                }
              ]
            }
          ]
        }
        """

        let story = try JSONDecoder().decode(DailyStory.self, from: Data(json.utf8))

        XCTAssertEqual(story.provenance?.generationMode, .legacy)
        XCTAssertEqual(story.provenance?.engineKind, "legacy")
        XCTAssertEqual(story.provenance?.engineLabel, "Legacy Story")
        XCTAssertEqual(story.provenance?.pipelineVersion, "legacy")
    }

    func testSummarizerStatusReflectsDegradedActiveEngineAfterConfigInvalidation() throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")
        let verifiedAt = Date(timeIntervalSince1970: 1_775_320_000)

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: verifiedAt,
            configurationSignature: "codex|\(originalExecutableURL.path)"
        )

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.summarizerStatus.lastCompletedAt, verifiedAt)
        XCTAssertEqual(appState.summarizerStatus.lastError, "Executable found. Retest required.")
    }

    func testEnvironmentInitInfersRuntimeEngineFromInjectedSummarizerForStatusBookkeeping() async throws {
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .openAI
        persistedConfig.apiBaseURL = "https://example.com/v1/responses"
        persistedConfig.apiModel = "gpt-5"
        persistedConfig.apiToken = "token-test-123"
        persistedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let executableURL = try makeStubExecutable(named: "codex")
        let environment = try makeEngineEnvironment()
        environment.summarizer = CLISummarizer(tool: .codex, executablePath: executableURL.path)

        let appState = AppState(
            environment: environment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(executableURL.path)")

        let verifiedAt = Date(timeIntervalSince1970: 1_775_330_000)
        appState.summarizerStatus = SummarizerRuntimeStatus(
            mode: DiaryEngine.codexCLI.displayName,
            isConfigured: true,
            lastCompletedAt: verifiedAt,
            lastError: nil
        )

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.configurationSignature, "codex|\(executableURL.path)")
        XCTAssertEqual(appState.engineStatuses[.openAI]?.lastVerifiedAt, nil)
    }

    func testInitPreservesPersistedUnverifiedDefaultEngineChoice() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .codexCLI
        persistedConfig.codexCLIPath = executableURL.path
        persistedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testInitPreservesPersistedGrayDefaultEngineChoice() throws {
        var persistedConfig = SummarizerConfig.default
        persistedConfig.defaultEngine = .claudeCLI
        persistedConfig.claudeCLIPath = "/definitely/missing/claude"
        persistedConfig.save(
            to: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        let (processEnvironment, isolatedHomeURL) = try makeIsolatedCLIProcessEnvironment()
        defer { try? FileManager.default.removeItem(at: isolatedHomeURL) }

        let appState = AppState(
            bootstrapServices: false,
            processEnvironment: processEnvironment,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.defaultEngine, .claudeCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.claudeCLI.displayName)
        XCTAssertFalse(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(appState.engineStatuses[.claudeCLI]?.state, .gray)
        XCTAssertEqual(appState.engineStatuses[.claudeCLI]?.detail, "Executable not found.")
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .claudeCLI
        )
    }

    func testRestartAfterActiveEngineDegradesPreservesPersistedYellowEngineChoice() throws {
        let originalExecutableURL = try makeStubExecutable(named: "codex")
        let updatedExecutableURL = try makeStubExecutable(named: "codex")

        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = originalExecutableURL.path

        let environment = try makeEngineEnvironment()
        let appState = AppState(
            environment: environment,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )
        appState.engineStatuses[.codexCLI] = EngineRuntimeStatus(
            state: .green,
            detail: "Smoke test succeeded.",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_775_340_000),
            configurationSignature: "codex|\(originalExecutableURL.path)"
        )
        appState.selectDefaultEngine(.codexCLI)

        config.codexCLIPath = updatedExecutableURL.path
        appState.applyEngineConfig(config)

        let relaunched = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(relaunched.defaultEngine, .codexCLI)
        XCTAssertNil(relaunched.environment?.summarizer)
        XCTAssertEqual(relaunched.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(relaunched.engineStatuses[.codexCLI]?.detail, "Executable found. Retest required.")
    }

    func testApplySummarizerConfigPromotesYellowRequestedEngineToDefaultChoice() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .codexCLI
        config.codexCLIPath = executableURL.path

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        appState.applySummarizerConfig(config)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testSelectDefaultEngineAllowsYellowEngineChoiceAndPersistsIt() throws {
        let executableURL = try makeStubExecutable(named: "codex")
        var config = SummarizerConfig.default
        config.defaultEngine = .none
        config.codexCLIPath = executableURL.path

        let appState = AppState(
            bootstrapServices: false,
            summarizerConfig: config,
            userDefaults: engineDefaults,
            keychain: engineKeychain,
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .yellow)

        appState.selectDefaultEngine(.codexCLI)

        XCTAssertEqual(appState.defaultEngine, .codexCLI)
        XCTAssertEqual(appState.summarizerStatus.mode, DiaryEngine.codexCLI.displayName)
        XCTAssertTrue(appState.summarizerStatus.isConfigured)
        XCTAssertEqual(
            SummarizerConfig.load(
                from: engineDefaults,
                keychain: engineKeychain,
                keychainService: "MainWindowViewModelTests"
            ).defaultEngine,
            .codexCLI
        )
    }

    func testSelectStoryParagraphUpdatesVisibleSourceEvents() async throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-07"
        let firstID = UUID()
        let secondID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 7, hour: 9).date!
        try writer.insert(
            EventRecord(
                id: firstID,
                sourceType: .clipboard,
                sourceApp: "Drafts",
                capturedAt: baseDate,
                dayKey: dayKey,
                text: "Outlined launch story",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "story-a"
            )
        )
        try writer.insert(
            EventRecord(
                id: secondID,
                sourceType: .notification,
                sourceApp: "Calendar",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: dayKey,
                text: "Design review in 10 minutes",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "story-b"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: StaticSummarizer(
                response: """
                {
                  "sections": [{
                    "id": "daily-journal",
                    "paragraphs": [
                      { "text": "# Summary\\n\\n- Outlined launch story", "sourceEventIDs": ["\(firstID.uuidString)"] },
                      { "text": "## Calendar\\n\\nDesign review in 10 minutes", "sourceEventIDs": ["\(secondID.uuidString)"] }
                    ]
                  }]
                }
                """
            ),
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        let appState = AppState(environment: environment, bootstrapServices: false)

        await appState.generateDailyNote(for: dayKey)
        appState.selectDate(dayKey)

        let paragraphIDs = appState.selectedStory?.sections.flatMap(\.paragraphs).map(\.id) ?? []
        XCTAssertGreaterThanOrEqual(paragraphIDs.count, 2)

        appState.selectStoryParagraph(paragraphIDs[1])

        XCTAssertEqual(appState.selectedStoryParagraphID, paragraphIDs[1])
        XCTAssertEqual(appState.selectedStorySourceEvents.count, 1)
        XCTAssertEqual(appState.selectedStorySourceEvents.first?.sourceType, .notification)
    }

    func testLoadDayPresentationLeavesLegacyDetailsUntouched() throws {
        let writer = try DatabaseWriter.inMemory()
        let dayKey = "2026-04-10"
        let figmaID = UUID()
        let notionID = UUID()
        let terminalID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 10, hour: 9).date!

        try writer.insert(
            EventRecord(
                id: figmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: baseDate,
                dayKey: dayKey,
                text: "Adjusted onboarding preview spacing.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-figma"
            )
        )
        try writer.insert(
            EventRecord(
                id: notionID,
                sourceType: .clipboard,
                sourceApp: "Notion",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: dayKey,
                text: "Compressed the demo into a cleaner narrative.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-notion"
            )
        )
        try writer.insert(
            EventRecord(
                id: terminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: baseDate.addingTimeInterval(600),
                dayKey: dayKey,
                text: "Ran the final verification build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "load-details-terminal"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )
        try writeStoryDay(
            dayKey: dayKey,
            markdown: """
            # 2026-04-10

            # Details

            ## Demo polish
            In Figma I refined the onboarding preview.

            ## Live narrative
            Notion helped keep the walkthrough honest.

            ## Recording readiness
            Terminal gave me the final verification pass.
            """,
            story: DailyStory(
                dayKey: dayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Demo polish
                                In Figma I refined the onboarding preview.

                                ## Live narrative
                                Notion helped keep the walkthrough honest.

                                ## Recording readiness
                                Terminal gave me the final verification pass.
                                """,
                                sourceEventIDs: [figmaID, notionID, terminalID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )

        let appState = AppState(environment: environment)
        appState.loadDayPresentation(for: dayKey)

        let paragraphs = try XCTUnwrap(appState.selectedStory?.sections.first?.paragraphs)
        XCTAssertEqual(paragraphs.map(\.id), ["daily-journal-2"])
        XCTAssertEqual(appState.selectedStoryParagraphID, "daily-journal-2")
        XCTAssertEqual(appState.selectedStorySourceEvents.map(\.id), [figmaID, notionID, terminalID])

        let persistedStory = try XCTUnwrap(environment.loadDailyStory(dayKey: dayKey))
        let persistedParagraphs = try XCTUnwrap(persistedStory.sections.first?.paragraphs)
        XCTAssertEqual(persistedParagraphs.map(\.id), ["daily-journal-2"])

        let persistedMarkdown = try String(contentsOf: vaultURL.appending(path: "\(dayKey).md"), encoding: .utf8)
        XCTAssertEqual(persistedMarkdown.components(separatedBy: "# Details").count - 1, 1)
        XCTAssertTrue(persistedMarkdown.contains("## Demo polish"))
        XCTAssertTrue(persistedMarkdown.contains("## Live narrative"))
        XCTAssertTrue(persistedMarkdown.contains("## Recording readiness"))
    }

    func testAppStateInitializationDoesNotMigrateLegacyStoriesAcrossVault() throws {
        let writer = try DatabaseWriter.inMemory()
        let newerDayKey = "2026-04-10"
        let olderDayKey = "2026-04-09"
        let newerFigmaID = UUID()
        let newerTerminalID = UUID()
        let olderNotionID = UUID()
        let olderXcodeID = UUID()
        let baseDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 4, day: 10, hour: 9).date!

        try writer.insert(
            EventRecord(
                id: newerFigmaID,
                sourceType: .clipboard,
                sourceApp: "Figma",
                capturedAt: baseDate,
                dayKey: newerDayKey,
                text: "Adjusted the preview spacing.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-newer-figma"
            )
        )
        try writer.insert(
            EventRecord(
                id: newerTerminalID,
                sourceType: .clipboard,
                sourceApp: "Terminal",
                capturedAt: baseDate.addingTimeInterval(300),
                dayKey: newerDayKey,
                text: "Ran the verification build.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-newer-terminal"
            )
        )
        try writer.insert(
            EventRecord(
                id: olderNotionID,
                sourceType: .clipboard,
                sourceApp: "Notion",
                capturedAt: baseDate.addingTimeInterval(-86_400),
                dayKey: olderDayKey,
                text: "Condensed the walkthrough script.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-older-notion"
            )
        )
        try writer.insert(
            EventRecord(
                id: olderXcodeID,
                sourceType: .clipboard,
                sourceApp: "Xcode",
                capturedAt: baseDate.addingTimeInterval(-86_100),
                dayKey: olderDayKey,
                text: "Checked the macOS build warnings.",
                auditText: nil,
                privacyAction: .keep,
                contentHash: "bulk-migrate-older-xcode"
            )
        )

        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            )
        )

        try writeStoryDay(
            dayKey: newerDayKey,
            markdown: """
            # 2026-04-10

            # Details

            ## Demo polish
            Figma tightened the preview.

            ## Verification
            Terminal confirmed the build.
            """,
            story: DailyStory(
                dayKey: newerDayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_500),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Demo polish
                                Figma tightened the preview.

                                ## Verification
                                Terminal confirmed the build.
                                """,
                                sourceEventIDs: [newerFigmaID, newerTerminalID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )
        try writeStoryDay(
            dayKey: olderDayKey,
            markdown: """
            # 2026-04-09

            # Details

            ## Narrative
            Notion reshaped the walkthrough.

            ## Build review
            Xcode exposed the warnings.
            """,
            story: DailyStory(
                dayKey: olderDayKey,
                generatedAt: Date(timeIntervalSince1970: 1_775_000_400),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(
                                id: "daily-journal-2",
                                text: """
                                # Details

                                ## Narrative
                                Notion reshaped the walkthrough.

                                ## Build review
                                Xcode exposed the warnings.
                                """,
                                sourceEventIDs: [olderNotionID, olderXcodeID]
                            )
                        ]
                    )
                ]
            ),
            environment: environment
        )

        let appState = AppState(environment: environment)

        let newerStory = try XCTUnwrap(environment.loadDailyStory(dayKey: newerDayKey))
        let olderStory = try XCTUnwrap(environment.loadDailyStory(dayKey: olderDayKey))
        XCTAssertEqual(newerStory.sections.first?.paragraphs.map(\.id), ["daily-journal-2"])
        XCTAssertEqual(olderStory.sections.first?.paragraphs.map(\.id), ["daily-journal-2"])

        let olderMarkdown = try String(contentsOf: vaultURL.appending(path: "\(olderDayKey).md"), encoding: .utf8)
        XCTAssertEqual(olderMarkdown.components(separatedBy: "# Details").count - 1, 1)
        XCTAssertTrue(olderMarkdown.contains("## Narrative"))
        XCTAssertTrue(olderMarkdown.contains("## Build review"))

        XCTAssertEqual(appState.availableDates, [newerDayKey, olderDayKey, OnboardingDemoStory.demoDayKey])
        XCTAssertEqual(appState.selectedDate, newerDayKey)
        XCTAssertEqual(appState.mainContentSelection, .diary(dayKey: newerDayKey))
    }

    func testAppStateLoadsSyncMemoryDefaultsAndExposesClosedPanelInitially() {
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )

        XCTAssertFalse(appState.isShowingSyncMemoryPanel)
        XCTAssertEqual(appState.syncMemoryConfig.dailySyncHour, 21)
        XCTAssertEqual(appState.syncMemoryConfig.dailySyncMinute, 0)
    }

    func testAppStateCanToggleSyncMemoryPanelVisibility() {
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )

        appState.openSyncMemoryPanel()
        XCTAssertTrue(appState.isShowingSyncMemoryPanel)

        appState.closeSyncMemoryPanel()
        XCTAssertFalse(appState.isShowingSyncMemoryPanel)
    }

    func testAppStateSelectsOtherSourceManagerWithoutChangingSelectedDiaryDate() {
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        appState.selectDate("2026-05-23")

        appState.selectOtherSourceManager(focusAddConnector: false)

        XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
        XCTAssertEqual(appState.selectedDate, "2026-05-23")
    }

    func testAppStateSelectsKnowledgeConnectorAndLoadsItsDocuments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        let contentURL = root.appendingPathComponent("content.md")
        let metadataURL = root.appendingPathComponent("metadata.json")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        let document = ImportedKnowledgeDocument(
            id: "doc-1",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-1",
            title: "Project Plan",
            sourcePath: "doc-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        try "# Project Plan".write(toFile: document.localContentPath, atomically: true, encoding: .utf8)
        try environment.databaseWriter.upsertImportedKnowledgeDocument(document)

        appState.selectKnowledgeConnector(instanceID: "feishu-main")

        XCTAssertEqual(appState.mainContentSelection, .knowledgeConnector(instanceID: "feishu-main"))
        XCTAssertEqual(appState.selectedKnowledgeDocuments.map(\.title), ["Project Plan"])
        XCTAssertEqual(appState.selectedKnowledgeDocumentMarkdown, "# Project Plan")
    }

    func testRefreshNotesIndexAutoSelectsDiaryMainContentSelection() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)

        appState.refreshNotesIndex()

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertEqual(appState.mainContentSelection, .diary(dayKey: "2026-04-08"))
    }

    func testRefreshNotesIndexPreservesOtherSourceSelectionWhenSelectedDateExists() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectDate("2026-04-08")
        appState.selectOtherSourceManager(focusAddConnector: false)

        appState.refreshNotesIndex()

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
    }

    func testRefreshNotesIndexPreservesKnowledgeConnectorSelectionWhenSelectedDateExists() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectDate("2026-04-08")
        appState.selectKnowledgeConnector(instanceID: "feishu-main")

        appState.refreshNotesIndex()

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertEqual(appState.mainContentSelection, .knowledgeConnector(instanceID: "feishu-main"))
    }

    func testRefreshNotesIndexPreservesKnowledgeDocumentSelectionWhenSelectedDateExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        let contentURL = root.appendingPathComponent("content.md")
        let metadataURL = root.appendingPathComponent("metadata.json")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        let document = ImportedKnowledgeDocument(
            id: "doc-1",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-1",
            title: "Project Plan",
            sourcePath: "doc-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        try "# Project Plan".write(toFile: document.localContentPath, atomically: true, encoding: .utf8)
        try environment.databaseWriter.upsertImportedKnowledgeDocument(document)
        appState.selectDate("2026-04-08")
        appState.selectKnowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-1")

        appState.refreshNotesIndex()

        XCTAssertEqual(appState.selectedDate, "2026-04-08")
        XCTAssertEqual(
            appState.mainContentSelection,
            .knowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-1")
        )
    }

    func testAppStateSelectsSecondKnowledgeDocumentMarkdown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        let firstContentURL = root.appendingPathComponent("alpha.md")
        let firstMetadataURL = root.appendingPathComponent("alpha.json")
        let secondContentURL = root.appendingPathComponent("beta.md")
        let secondMetadataURL = root.appendingPathComponent("beta.json")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        let firstDocument = ImportedKnowledgeDocument(
            id: "doc-alpha",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-alpha",
            title: "Alpha Plan",
            sourcePath: "doc-alpha-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash-alpha",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: firstContentURL.path,
            localMetadataPath: firstMetadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        let secondDocument = ImportedKnowledgeDocument(
            id: "doc-beta",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-beta",
            title: "Beta Plan",
            sourcePath: "doc-beta-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash-beta",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: secondContentURL.path,
            localMetadataPath: secondMetadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        try "# Alpha Plan".write(toFile: firstDocument.localContentPath, atomically: true, encoding: .utf8)
        try "# Beta Plan".write(toFile: secondDocument.localContentPath, atomically: true, encoding: .utf8)
        try environment.databaseWriter.upsertImportedKnowledgeDocuments([secondDocument, firstDocument])

        appState.selectKnowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-beta")

        XCTAssertEqual(
            appState.mainContentSelection,
            .knowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-beta")
        )
        XCTAssertEqual(appState.selectedKnowledgeDocuments.map(\.title), ["Alpha Plan", "Beta Plan"])
        XCTAssertEqual(appState.selectedKnowledgeDocument?.id, "doc-beta")
        XCTAssertEqual(appState.selectedKnowledgeDocumentMarkdown, "# Beta Plan")
    }

    func testAppStateLimitsLargeKnowledgeDocumentMarkdownPreview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        let contentURL = root.appendingPathComponent("large-content.md")
        let metadataURL = root.appendingPathComponent("large-metadata.json")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        let document = ImportedKnowledgeDocument(
            id: "doc-large",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-large",
            title: "Large Plan",
            sourcePath: "doc-large-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash-large",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        let fullMarkdown = "# Large Plan\n\n" + String(repeating: "A", count: 300_000)
        try fullMarkdown.write(toFile: document.localContentPath, atomically: true, encoding: .utf8)
        try environment.databaseWriter.upsertImportedKnowledgeDocument(document)

        appState.selectKnowledgeConnector(instanceID: "feishu-main")

        let preview = try XCTUnwrap(appState.selectedKnowledgeDocumentMarkdown)
        XCTAssertLessThan(preview.count, fullMarkdown.count)
        XCTAssertTrue(preview.hasSuffix("\n\n[Preview truncated]"))
    }

    func testDeletingSelectedKnowledgeConnectorRoutesToOtherSourceManager() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectKnowledgeConnector(instanceID: "feishu-main")

        appState.didDeleteKnowledgeConnector(instanceID: "feishu-main")

        XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
    }

    func testDeletingSelectedKnowledgeDocumentConnectorRoutesToOtherSourceManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        let contentURL = root.appendingPathComponent("content.md")
        let metadataURL = root.appendingPathComponent("metadata.json")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let appState = AppState(environment: environment, bootstrapServices: false)
        let document = ImportedKnowledgeDocument(
            id: "doc-1",
            connectorInstanceID: "feishu-main",
            connectorID: .feishuImport,
            remoteID: "remote-1",
            title: "Project Plan",
            sourcePath: "doc-token",
            remoteURL: nil,
            mimeType: "text/markdown",
            contentHash: "hash",
            remoteUpdatedAt: nil,
            firstImportedAt: Date(timeIntervalSince1970: 1_778_000_000),
            lastSyncedAt: Date(timeIntervalSince1970: 1_778_000_100),
            deletedAt: nil,
            localContentPath: contentURL.path,
            localMetadataPath: metadataURL.path,
            normalizationVersion: 1,
            originKind: "feishu"
        )
        try "# Project Plan".write(toFile: document.localContentPath, atomically: true, encoding: .utf8)
        try environment.databaseWriter.upsertImportedKnowledgeDocument(document)
        appState.selectKnowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-1")

        appState.didDeleteKnowledgeConnector(instanceID: "feishu-main")

        XCTAssertEqual(appState.mainContentSelection, .otherSourceManager(focusAddConnector: false))
    }

    func testDeletingUnrelatedKnowledgeConnectorLeavesSelectionUnchanged() throws {
        let environment = try makeReaderEnvironment()
        let appState = AppState(environment: environment, bootstrapServices: false)
        appState.selectKnowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-1")

        appState.didDeleteKnowledgeConnector(instanceID: "notion-main")

        XCTAssertEqual(
            appState.mainContentSelection,
            .knowledgeDocument(connectorInstanceID: "feishu-main", documentID: "doc-1")
        )
    }

    func testSyncNowCopiesLatestDiaryIntoConfiguredDestinations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let databaseURL = root.appendingPathComponent("events.sqlite")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "# Day".write(
            to: vault.appendingPathComponent("2026-04-14.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = try AppEnvironment(
            databasePath: databaseURL.path,
            vaultURL: vault,
            summarizer: nil
        )
        let suiteName = "MainWindowViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            environment: environment,
            bootstrapServices: false,
            userDefaults: defaults,
            keychain: AppStateTestKeychainStore(),
            keychainService: "MainWindowViewModelTests"
        )
        appState.syncMemoryConfig.obsidian.isEnabled = true
        appState.syncMemoryConfig.obsidian.resolvedPath = root
            .appendingPathComponent("Obsidian/KnowYou/Daily Memories", isDirectory: true)
            .path
        appState.syncMemoryConfig.openClaw.isEnabled = true
        appState.syncMemoryConfig.openClaw.resolvedPath = root
            .appendingPathComponent("OpenClaw/know-you-memory", isDirectory: true)
            .path

        appState.syncMemoryNow()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Obsidian/KnowYou/Daily Memories/2026-04-14.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("OpenClaw/know-you-memory/2026-04-14.md").path
        ))
        XCTAssertEqual(appState.statusMessage, "Synced 1 note to 2 destinations")
    }

    private func makeModelStory(dayKey: String, eventID: UUID) -> DailyStory {
        DailyStory(
            dayKey: dayKey,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_100),
            sections: [
                DailyStorySection(
                    id: "daily-journal",
                    title: "",
                    paragraphs: [
                        DailyStoryParagraph(
                            id: "daily-journal-0",
                            text: "# 你今天做得很棒\n旧的成功内容",
                            sourceEventIDs: [eventID]
                        )
                    ]
                )
            ],
            provenance: StoryProvenance(
                generationMode: .model,
                engineKind: DiaryEngine.codexCLI.rawValue,
                engineLabel: DiaryEngine.codexCLI.displayName,
                model: nil,
                pipelineVersion: "diary-story-v1",
                curatedEventCount: 1
            )
        )
    }

    private func makeEngineEnvironment(
        updateService: any UpdateServing = StubUpdateService(result: .success(nil)),
        directAppUpdater: (any DirectAppUpdating)? = nil,
        externalURLOpener: @escaping @MainActor @Sendable (URL) -> Void = { _ in }
    ) throws -> AppEnvironment {
        let writer = try DatabaseWriter.inMemory()
        let vaultURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return AppEnvironment(
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).sqlite"),
            vaultURL: vaultURL,
            databaseWriter: writer,
            summarizer: nil,
            notificationReader: RecordingNotificationReader(),
            dailyAutomationPlanner: DailyAutomationPlanner(
                backfillPlanner: BackfillPlanner(calendar: Calendar(identifier: .gregorian))
            ),
            updateService: updateService,
            directAppUpdater: directAppUpdater,
            externalURLOpener: externalURLOpener
        )
    }

    private func makeStubExecutable(named name: String) throws -> URL {
        let directoryURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let executableURL = directoryURL.appending(path: name)
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return executableURL
    }
}
