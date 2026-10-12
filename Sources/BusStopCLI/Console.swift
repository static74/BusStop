import BusStopCore
import Foundation

/// Exit statuses of the `busstop` command.
enum ExitStatus {
    static let success: Int32 = 0
    /// Something went wrong at run time (unreadable file, encoding failure).
    static let failure: Int32 = 1
    /// The command line was wrong.
    static let usage: Int32 = 2
}

/// An error that ends the command with a message on standard error.
struct CLIFailure: Error, Equatable {
    var message: String
    var status: Int32

    static func usage(_ message: String) -> CLIFailure {
        CLIFailure(message: message, status: ExitStatus.usage)
    }

    static func runtime(_ message: String) -> CLIFailure {
        CLIFailure(message: message, status: ExitStatus.failure)
    }
}

/// Unbuffered writes to standard output and standard error.
///
/// Writes go straight to the file descriptors, so `--watch` lines appear
/// immediately even when the output is piped. A closed pipe ends the process
/// through SIGPIPE, as with other command-line tools. Any other failed write
/// to standard output (a full disk, an I/O error, a descriptor that is not
/// open for writing) ends the command with status 1, so a truncated
/// `busstop --raw > capture.json` never looks like a success. Writes to
/// standard error stay best effort: there is nowhere left to report their
/// failure.
enum Console {
    static func out(_ text: String) {
        writeOut(Data(text.utf8))
    }

    static func out(_ data: Data) {
        writeOut(data)
    }

    static func err(_ text: String) {
        guard !text.isEmpty else { return }
        try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
    }

    /// Prints `text` and makes sure the output ends with exactly one newline.
    static func printDocument(_ text: String) {
        var document = text
        while document.hasSuffix("\n") { document.removeLast() }
        out(document + "\n")
    }

    /// Prints the error and exits with its status. Usage errors get a hint
    /// pointing at `--help`.
    ///
    /// The message can quote a capture file (a key or a value that failed to
    /// decode), so it goes through `Format.terminalSafe` like any other text
    /// that did not come from Bus Stop itself.
    static func fail(_ error: Error) -> Never {
        let failure = (error as? CLIFailure) ?? CLIFailure.runtime(String(describing: error))
        err("busstop: \(Format.terminalSafe(failure.message))\n")
        if failure.status == ExitStatus.usage {
            err("Run 'busstop --help' for usage.\n")
        }
        exit(failure.status)
    }

    /// Writes to standard output, or reports the error and exits with status 1.
    private static func writeOut(_ data: Data) {
        guard !data.isEmpty else { return }
        do {
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            err("busstop: cannot write the output: \(Format.terminalSafe(error.localizedDescription))\n")
            exit(ExitStatus.failure)
        }
    }
}
