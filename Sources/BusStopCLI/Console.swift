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
/// through SIGPIPE, as with other command-line tools.
enum Console {
    static func out(_ text: String) {
        write(Data(text.utf8), to: FileHandle.standardOutput)
    }

    static func out(_ data: Data) {
        write(data, to: FileHandle.standardOutput)
    }

    static func err(_ text: String) {
        write(Data(text.utf8), to: FileHandle.standardError)
    }

    /// Prints `text` and makes sure the output ends with exactly one newline.
    static func printDocument(_ text: String) {
        var document = text
        while document.hasSuffix("\n") { document.removeLast() }
        out(document + "\n")
    }

    /// Prints the error and exits with its status. Usage errors get a hint
    /// pointing at `--help`.
    static func fail(_ error: Error) -> Never {
        let failure = (error as? CLIFailure) ?? CLIFailure.runtime(String(describing: error))
        err("busstop: \(failure.message)\n")
        if failure.status == ExitStatus.usage {
            err("Run 'busstop --help' for usage.\n")
        }
        exit(failure.status)
    }

    private static func write(_ data: Data, to handle: FileHandle) {
        guard !data.isEmpty else { return }
        try? handle.write(contentsOf: data)
    }
}
