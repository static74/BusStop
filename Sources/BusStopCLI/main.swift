// busstop: the Bus Stop command-line tool.
//
//   busstop [--json | --markdown | --raw] [--watch] [--demo <scenario>]
//           [--input <raw.json>] [--no-redact] [--no-smc] [--version] [--help]
//
// See `ArgumentParser.helpText` for the full description and docs/SPEC.md §3.6.

import BusStopCore
import Foundation

/// Parses the command line, does the work and exits with the right status.
@MainActor
func runBusStop(_ arguments: [String]) -> Never {
    let options: CLIOptions
    do {
        options = try ArgumentParser.parse(arguments)
    } catch {
        Console.fail(error)
    }

    if options.showHelp {
        Console.out(ArgumentParser.helpText)
        exit(ExitStatus.success)
    }
    if options.showVersion {
        Console.out("busstop \(VersionInfo.line)\n")
        exit(ExitStatus.success)
    }
    if options.watch {
        WatchSession.run(options)
    }

    do {
        let raw = try Pipeline.capture(for: options)
        Console.printDocument(try Pipeline.render(raw, options: options))
    } catch {
        Console.fail(error)
    }
    exit(ExitStatus.success)
}

runBusStop(Array(CommandLine.arguments.dropFirst()))
