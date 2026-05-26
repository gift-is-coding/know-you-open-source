import Foundation

struct MyWikiContextPackCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct MyWikiContextPackCommand {
    static let launchArgument = "--my-wiki-context"

    static func run(arguments: [String]) -> MyWikiContextPackCommandResult {
        do {
            let configuration = try parse(arguments: arguments)
            if configuration.showsHelp {
                return MyWikiContextPackCommandResult(exitCode: 0, stdout: "", stderr: usage())
            }

            let pack = MyWikiContextPackService().contextPack(
                for: MyWikiContextPackRequest(
                    projectRoot: configuration.projectRoot,
                    query: configuration.background,
                    maxItems: configuration.maxItems,
                    characterBudget: configuration.characterBudget
                )
            )

            let encoder = JSONEncoder()
            if configuration.prettyPrint {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            }
            let data = try encoder.encode(pack)
            let json = String(decoding: data, as: UTF8.self) + "\n"
            return MyWikiContextPackCommandResult(exitCode: 0, stdout: json, stderr: "")
        } catch let error as MyWikiContextPackCommandError {
            return MyWikiContextPackCommandResult(
                exitCode: 2,
                stdout: "",
                stderr: error.localizedDescription + "\n\n" + usage()
            )
        } catch {
            return MyWikiContextPackCommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "Failed to generate My Wiki context: \(error.localizedDescription)\n"
            )
        }
    }

    private static func parse(arguments: [String]) throws -> MyWikiContextPackCommandConfiguration {
        var projectRoot: URL?
        var background: String?
        var maxItems = 8
        var characterBudget = 6_000
        var prettyPrint = false
        var showsHelp = false

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case launchArgument:
                index += 1
            case "--project-root":
                projectRoot = URL(fileURLWithPath: try value(after: argument, in: arguments, index: index))
                index += 2
            case "--query":
                background = try value(after: argument, in: arguments, index: index)
                index += 2
            case "--background":
                background = try value(after: argument, in: arguments, index: index)
                index += 2
            case "--max-items":
                let rawValue = try value(after: argument, in: arguments, index: index)
                guard let parsed = Int(rawValue) else {
                    throw MyWikiContextPackCommandError.invalidInteger(option: argument, value: rawValue)
                }
                maxItems = parsed
                index += 2
            case "--character-budget":
                let rawValue = try value(after: argument, in: arguments, index: index)
                guard let parsed = Int(rawValue) else {
                    throw MyWikiContextPackCommandError.invalidInteger(option: argument, value: rawValue)
                }
                characterBudget = parsed
                index += 2
            case "--pretty":
                prettyPrint = true
                index += 1
            case "--help", "-h":
                showsHelp = true
                index += 1
            default:
                throw MyWikiContextPackCommandError.unknownOption(argument)
            }
        }

        if showsHelp {
            return MyWikiContextPackCommandConfiguration(
                projectRoot: URL(fileURLWithPath: "."),
                background: "",
                maxItems: maxItems,
                characterBudget: characterBudget,
                prettyPrint: prettyPrint,
                showsHelp: true
            )
        }

        guard let projectRoot else {
            throw MyWikiContextPackCommandError.missingRequiredOption("--project-root")
        }
        guard let background, background.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MyWikiContextPackCommandError.missingRequiredOption("--background")
        }

        return MyWikiContextPackCommandConfiguration(
            projectRoot: projectRoot,
            background: background,
            maxItems: maxItems,
            characterBudget: characterBudget,
            prettyPrint: prettyPrint,
            showsHelp: false
        )
    }

    private static func value(after option: String, in arguments: [String], index: Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw MyWikiContextPackCommandError.missingValue(option)
        }
        let value = arguments[valueIndex]
        guard value.hasPrefix("--") == false else {
            throw MyWikiContextPackCommandError.missingValue(option)
        }
        return value
    }

    private static func usage() -> String {
        """
        Usage: KnowYou --my-wiki-context --project-root <path> --background <text> [--max-items <count>] [--character-budget <count>] [--pretty]
               KnowYou --my-wiki-context --project-root <path> --query <text> [--max-items <count>] [--character-budget <count>] [--pretty]
        """
    }
}

private struct MyWikiContextPackCommandConfiguration {
    let projectRoot: URL
    let background: String
    let maxItems: Int
    let characterBudget: Int
    let prettyPrint: Bool
    let showsHelp: Bool
}

private enum MyWikiContextPackCommandError: LocalizedError, Equatable {
    case missingRequiredOption(String)
    case missingValue(String)
    case invalidInteger(option: String, value: String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case let .missingRequiredOption(option):
            return "Missing required option: \(option)"
        case let .missingValue(option):
            return "Missing value for \(option)"
        case let .invalidInteger(option, value):
            return "Invalid integer for \(option): \(value)"
        case let .unknownOption(option):
            return "Unknown option: \(option)"
        }
    }
}
