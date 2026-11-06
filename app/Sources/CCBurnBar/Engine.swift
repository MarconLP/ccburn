import Foundation

/// One `ccburn --json` frame: the colored screen plus the headline numbers.
struct Frame: Decodable {
    let frame: String
    let rate_5m: Double
    let rate_15m: Double
    let rate_60m: Double
    let today: Double
    let projected_today: Double
    let updated: String
}

enum EngineError: LocalizedError {
    case missingScript
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "ccburn script not found: it ships in the app's Resources, or set CCBURN_SCRIPT"
        case .failed(let message):
            return message
        }
    }
}

/// Runs the bundled ccburn script, which stays the single source of truth for
/// scanning, pricing and drawing the screen. The app only displays its frame.
final class Engine {
    let scriptURL: URL

    init() throws {
        if let override = ProcessInfo.processInfo.environment["CCBURN_SCRIPT"] {
            scriptURL = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else if let bundled = Bundle.main.url(forResource: "ccburn", withExtension: nil) {
            scriptURL = bundled
        } else {
            throw EngineError.missingScript
        }
    }

    /// Calls `completion` on a background queue.
    func run(columns: Int, height: Int, completion: @escaping (Result<Frame, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, "--json", "--width", String(columns), "--height", String(height)]
        var env = ProcessInfo.processInfo.environment
        // A GUI launch gets launchd's bare PATH; prefer a Homebrew python3, fall back to the system one.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let errLock = NSLock()
        var errData = Data()
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            errLock.lock()
            errData.append(chunk)
            errLock.unlock()
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                try process.run()
            } catch {
                err.fileHandleForReading.readabilityHandler = nil
                completion(.failure(EngineError.failed("could not start python3: \(error.localizedDescription)")))
                return
            }
            // A first scan of a cold cache takes seconds; anything past a minute is stuck.
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                if process.isRunning { process.terminate() }
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            err.fileHandleForReading.readabilityHandler = nil
            errLock.lock()
            let stderr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            errLock.unlock()

            guard process.terminationStatus == 0 else {
                let reason = stderr.isEmpty ? "ccburn exited with status \(process.terminationStatus)" : stderr
                completion(.failure(EngineError.failed(reason)))
                return
            }
            do {
                completion(.success(try JSONDecoder().decode(Frame.self, from: data)))
            } catch {
                completion(.failure(EngineError.failed("unreadable ccburn output: \(error.localizedDescription)")))
            }
        }
    }

    /// Blocking variant for the `--snapshot` mode.
    func runSync(columns: Int, height: Int) -> Result<Frame, Error> {
        let done = DispatchSemaphore(value: 0)
        var result: Result<Frame, Error> = .failure(EngineError.failed("no result"))
        run(columns: columns, height: height) {
            result = $0
            done.signal()
        }
        done.wait()
        return result
    }
}
