import BusStopCore
import Testing
@testable import BusStopCLI

/// The `busstop` command-line parser: values, sources and the combinations
/// it rejects.
@Suite("CLI arguments")
struct ArgumentParserTests {
    @Test func inputNeedsAPath() {
        #expect(throws: CLIFailure.usage("--input needs a file path, or - for standard input")) {
            try ArgumentParser.parse(["--input", "--json"])
        }
    }

    @Test func dashReadsStandardInput() throws {
        #expect(try ArgumentParser.parse(["--input=-"]).source == .file("-"))
        #expect(try ArgumentParser.parse(["--input", "-"]).source == .file("-"))
    }

    @Test func unknownOption() {
        #expect(throws: CLIFailure.usage("unknown option '--bogus'")) {
            try ArgumentParser.parse(["--bogus"])
        }
    }

    @Test func conflictingFormats() {
        #expect(throws: CLIFailure.usage("--json and --raw cannot be combined; choose one output format")) {
            try ArgumentParser.parse(["--json", "--raw"])
        }
    }

    @Test func watchCombinations() {
        let formatError = CLIFailure.usage("--watch prints connection events; combine it with --json or nothing")
        #expect(throws: formatError) { try ArgumentParser.parse(["--watch", "--raw"]) }
        #expect(throws: formatError) { try ArgumentParser.parse(["--watch", "--markdown"]) }
        #expect(throws: CLIFailure.usage("--watch needs this Mac or --demo; a capture file never changes")) {
            try ArgumentParser.parse(["--watch", "--input", "capture.json"])
        }
    }

    @Test func repeatedSource() {
        #expect(throws: CLIFailure.usage("--demo was given more than once")) {
            try ArgumentParser.parse(["--demo", "travel", "--demo", "travel"])
        }
    }

    @Test func demoByName() throws {
        #expect(try ArgumentParser.parse(["--demo", "travel"]).source == .demo(.travel))
        #expect(try ArgumentParser.parse(["--demo=studio-desk"]).source == .demo(.studioDesk))
    }
}
