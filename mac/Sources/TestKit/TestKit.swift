import Foundation

/// A minimal test harness.
///
/// XCTest and swift-testing both ship inside Xcode, and this machine has Command
/// Line Tools only — so `swift test` cannot work here. Rather than ship untested
/// code, Lumiere runs its suite as a plain executable: `swift run LumiereTests`.
///
/// The API deliberately mirrors swift-testing's shape (`suite`, `test`, `expect`)
/// so that if Xcode is ever installed, porting is close to a find-and-replace.
@MainActor
public final class TestRunner {

    private var passed = 0
    private var failed = 0
    private var currentTest = ""
    private var currentTestFailed = false
    private var failureLog: [String] = []

    public init() {}

    // MARK: - Structure

    public func suite(_ name: String, _ body: (TestRunner) throws -> Void) {
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        do {
            try body(self)
        } catch {
            failed += 1
            failureLog.append("  \(name): suite threw \(error)")
            print("  \u{001B}[31m✗\u{001B}[0m suite threw \(error)")
        }
    }

    public func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        currentTestFailed = false
        do {
            try body()
        } catch {
            recordFailure("threw \(error)", file: #file, line: #line)
        }
        finishTest(name)
    }

    /// The async variant. Tests that touch actors must use this rather than
    /// blocking on a semaphore — the runner is main-actor isolated, so a blocking
    /// wait deadlocks against any continuation that needs the main actor.
    public func test(_ name: String, _ body: () async throws -> Void) async {
        currentTest = name
        currentTestFailed = false
        do {
            try await body()
        } catch {
            recordFailure("threw \(error)", file: #file, line: #line)
        }
        finishTest(name)
    }

    private func finishTest(_ name: String) {
        if currentTestFailed {
            failed += 1
        } else {
            passed += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(name)")
        }
    }

    /// Async suite body, for files whose tests are all async.
    public func suite(_ name: String, _ body: (TestRunner) async throws -> Void) async {
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        do {
            try await body(self)
        } catch {
            failed += 1
            failureLog.append("  \(name): suite threw \(error)")
            print("  \u{001B}[31m✗\u{001B}[0m suite threw \(error)")
        }
    }

    // MARK: - Assertions

    public func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !condition else { return }
        let detail = message()
        recordFailure(detail.isEmpty ? "expectation failed" : detail, file: file, line: line)
    }

    public func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        var detail = "expected \(expected), got \(actual)"
        let extra = message()
        if !extra.isEmpty { detail = "\(extra) — \(detail)" }
        recordFailure(detail, file: file, line: line)
    }

    public func expectNil<T>(
        _ value: T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard value != nil else { return }
        let extra = message()
        recordFailure(extra.isEmpty ? "expected nil, got \(value!)" : extra, file: file, line: line)
    }

    public func expectNotNil<T>(
        _ value: T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard value == nil else { return }
        let extra = message()
        recordFailure(extra.isEmpty ? "expected a value, got nil" : extra, file: file, line: line)
    }

    public func expectThrows(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            let extra = message()
            recordFailure(extra.isEmpty ? "expected a throw, none happened" : extra, file: file, line: line)
        } catch {
            // Expected.
        }
    }

    // MARK: - Reporting

    private func recordFailure(_ detail: String, file: StaticString, line: UInt) {
        if !currentTestFailed {
            print("  \u{001B}[31m✗\u{001B}[0m \(currentTest)")
            currentTestFailed = true
        }
        let location = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
        print("      \(detail)  (\(location))")
        failureLog.append("  \(currentTest) — \(detail)  (\(location))")
    }

    /// Prints the summary and exits with a status code, so this doubles as a CI gate.
    public func finish() -> Never {
        let total = passed + failed
        print("")
        if failed == 0 {
            print("\u{001B}[32m\(total) tests passed\u{001B}[0m")
            exit(0)
        }
        print("\u{001B}[31m\(failed) of \(total) tests failed\u{001B}[0m")
        for line in failureLog { print(line) }
        exit(1)
    }
}
