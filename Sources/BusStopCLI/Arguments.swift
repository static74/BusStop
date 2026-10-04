import BusStopCore
import Foundation

/// What the CLI prints.
enum OutputFormat: String, Sendable, Equatable {
    /// `Exporter.textTree`, the default.
    case text
    /// `Exporter.json` of the interpreted snapshot.
    case json
    /// `Exporter.markdown` report.
    case markdown
    /// `Exporter.rawJSON` of the capture itself (bug reports, test fixtures).
    case raw
}

/// Where the raw capture comes from.
enum CaptureSource: Sendable, Equatable {
    /// This Mac, through `RegistryCapture` / `LiveMonitor`.
    case live
    /// A built-in sample setup.
    case demo(DemoScenario)
    /// A capture saved with `--raw`. `"-"` means standard input.
    case file(String)
}

/// Parsed command line.
struct CLIOptions: Sendable, Equatable {
    var format: OutputFormat = .text
    var source: CaptureSource = .live
    var watch = false
    var redact = true
    var includeSMC = true
    var showVersion = false
    var showHelp = false
}

/// Hand-written parser for the `busstop` command line.
///
/// Accepts `--name value` and `--name=value` for options that take a value.
/// Rejects unknown options, stray arguments and contradictory combinations
/// with a `CLIFailure.usage` error, which the entry point turns into exit
/// status 2.
enum ArgumentParser {
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var formatFlag: String?
        var sourceFlag: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            var name = argument
            var inlineValue: String?
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                name = String(argument[..<equals])
                inlineValue = String(argument[argument.index(after: equals)...])
            }

            /// The value of an option that needs one, from `--name=value` or
            /// the next argument.
            func requireValue(_ hint: String) throws -> String {
                if let inlineValue {
                    guard !inlineValue.isEmpty else { throw CLIFailure.usage("\(name) needs \(hint)") }
                    return inlineValue
                }
                guard index < arguments.count else { throw CLIFailure.usage("\(name) needs \(hint)") }
                let value = arguments[index]
                // "-" is a valid value (standard input); other dash words are options.
                if value.hasPrefix("-") && value != "-" { throw CLIFailure.usage("\(name) needs \(hint)") }
                index += 1
                return value
            }

            func rejectInlineValue() throws {
                if inlineValue != nil { throw CLIFailure.usage("\(name) does not take a value") }
            }

            switch name {
            case "--json", "--markdown", "--raw":
                try rejectInlineValue()
                if let formatFlag, formatFlag != name {
                    throw CLIFailure.usage("\(formatFlag) and \(name) cannot be combined; choose one output format")
                }
                formatFlag = name
                switch name {
                case "--json": options.format = .json
                case "--markdown": options.format = .markdown
                default: options.format = .raw
                }

            case "--watch":
                try rejectInlineValue()
                options.watch = true

            case "--demo":
                let value = try requireValue("a scenario name (\(scenarioList))")
                try claimSource(name, current: &sourceFlag)
                guard let scenario = scenario(named: value) else {
                    throw CLIFailure.usage("unknown demo scenario '\(value)'. Valid names: \(scenarioList)")
                }
                options.source = .demo(scenario)

            case "--input":
                let value = try requireValue("a file path, or - for standard input")
                try claimSource(name, current: &sourceFlag)
                options.source = .file(value)

            case "--no-redact":
                try rejectInlineValue()
                options.redact = false

            case "--no-smc":
                try rejectInlineValue()
                options.includeSMC = false

            case "--version":
                try rejectInlineValue()
                options.showVersion = true

            case "--help", "-h":
                try rejectInlineValue()
                options.showHelp = true

            default:
                if argument.hasPrefix("-") && argument != "-" {
                    throw CLIFailure.usage("unknown option '\(argument)'")
                }
                throw CLIFailure.usage("unexpected argument '\(argument)'")
            }
        }

        // Help and version short-circuit everything else.
        if options.showHelp || options.showVersion { return options }

        if options.watch {
            switch options.format {
            case .text, .json:
                break
            case .markdown, .raw:
                throw CLIFailure.usage("--watch prints connection events; combine it with --json or nothing")
            }
            if case .file = options.source {
                throw CLIFailure.usage("--watch needs this Mac or --demo; a capture file never changes")
            }
        }
        return options
    }

    /// Records which flag chose the capture source, rejecting a second one.
    private static func claimSource(_ flag: String, current: inout String?) throws {
        if let current {
            if current == flag { throw CLIFailure.usage("\(flag) was given more than once") }
            throw CLIFailure.usage("\(current) and \(flag) cannot be combined")
        }
        current = flag
    }

    /// The scenario with this name. Exact raw values match first; otherwise
    /// case, hyphens, underscores and spaces are ignored ("studio-desk").
    static func scenario(named name: String) -> DemoScenario? {
        if let exact = DemoScenario(rawValue: name) { return exact }
        let wanted = simplified(name)
        return DemoScenario.allCases.first { simplified($0.rawValue) == wanted }
    }

    private static func simplified(_ name: String) -> String {
        name.lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " }
    }

    /// "studioDesk, travel, dockStation, unplugged".
    static var scenarioList: String {
        DemoScenario.allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// The text printed by `--help`.
    static var helpText: String {
        let scenarios = DemoScenario.allCases
            .map { "                      \($0.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \($0.title)" }
            .joined(separator: "\n")
        return """
        busstop \(BusStopVersion.string): a live map of every port on your Mac.

        Usage: busstop [--json | --markdown | --raw] [--watch] [--demo <scenario>]
                       [--input <file>] [--no-redact] [--no-smc]
               busstop --version | --help

        Output (choose one; the default is a text tree):
          --json            The interpreted snapshot as JSON.
          --markdown        A Markdown report.
          --raw             The raw IORegistry capture as JSON. Attach it to bug
                            reports; it also works as a test fixture.

        Source (the default is this Mac):
          --demo <name>     A built-in sample setup:
        \(scenarios)
          --input <file>    A raw capture saved with --raw. Use - to read
                            standard input.

        Watching:
          --watch           Print one line per connection change until Control-C.
                            With --json, print one JSON object per line instead.
                            With --demo, a sample device is unplugged and plugged
                            back in every few seconds.

        Other:
          --no-redact       Keep serial numbers and the computer name in --json,
                            --markdown and --raw output (redacted by default).
          --no-smc          Do not read per-port power from the SMC.
          --version         Print the version.
          -h, --help        Print this help.

        Examples:
          busstop
          busstop --json > snapshot.json
          busstop --raw > capture.json
          busstop --input capture.json --markdown
          busstop --watch --demo studioDesk

        Exit status: 0 on success, 1 on a runtime error, 2 on a usage error.
        Project page: \(BusStopVersion.projectURL)

        """
    }
}
