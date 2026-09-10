import Foundation

public struct HeadlessOptions {
    public let input: String
    public let outputDirectory: URL
    public let audioFormat: AudioFormat
    public let manifestPath: URL?
    public let toolsPath: URL?
    public let includePlaylist: Bool
    public let maxRetries: Int

    public init(input: String, outputDirectory: URL, audioFormat: AudioFormat = .m4a, manifestPath: URL? = nil, toolsPath: URL? = nil, includePlaylist: Bool = true, maxRetries: Int = 2) {
        self.input = input
        self.outputDirectory = outputDirectory
        self.audioFormat = audioFormat
        self.manifestPath = manifestPath
        self.toolsPath = toolsPath
        self.includePlaylist = includePlaylist
        self.maxRetries = maxRetries
    }

    public static func parse(_ arguments: [String]) throws -> HeadlessOptions {
        guard arguments.contains("--headless") else { throw HeadlessOptionError.missingHeadlessFlag }
        var input: String?
        var output: URL?
        var audioFormat: AudioFormat = .m4a
        var manifestPath: URL?
        var toolsPath: URL?
        var includePlaylist = true
        var maxRetries = 2
        var index = 0

        func value(after flag: String) throws -> String {
            let next = index + 1
            guard next < arguments.count else { throw HeadlessOptionError.missingValue(flag) }
            index = next
            return arguments[next]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--headless": break
            case "--url": input = try value(after: argument)
            case "--output": output = URL(fileURLWithPath: try value(after: argument), isDirectory: true)
            case "--audio-format":
                let raw = try value(after: argument).lowercased()
                guard let parsed = AudioFormat.allCases.first(where: { $0.rawValue.lowercased() == raw }) else { throw HeadlessOptionError.invalidAudioFormat(raw) }
                audioFormat = parsed
            case "--manifest": manifestPath = URL(fileURLWithPath: try value(after: argument))
            case "--tools": toolsPath = URL(fileURLWithPath: try value(after: argument), isDirectory: true)
            case "--no-playlist": includePlaylist = false
            case "--max-retries":
                guard let parsed = Int(try value(after: argument)), (0...10).contains(parsed) else { throw HeadlessOptionError.invalidRetries }
                maxRetries = parsed
            case "--help": throw HeadlessOptionError.help
            default:
                if argument.hasPrefix("-") { throw HeadlessOptionError.unknownOption(argument) }
                if input == nil { input = argument } else { throw HeadlessOptionError.multipleInputs }
            }
            index += 1
        }

        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HeadlessOptionError.missingInput }
        guard let output else { throw HeadlessOptionError.missingValue("--output") }
        return HeadlessOptions(input: input, outputDirectory: output, audioFormat: audioFormat, manifestPath: manifestPath, toolsPath: toolsPath, includePlaylist: includePlaylist, maxRetries: maxRetries)
    }
}

public enum HeadlessOptionError: LocalizedError {
    case missingHeadlessFlag, missingInput, missingValue(String), invalidAudioFormat(String), invalidRetries, unknownOption(String), multipleInputs, help

    public var errorDescription: String? {
        switch self {
        case .missingHeadlessFlag: return "Headless mode requires --headless."
        case .missingInput: return "Provide a YouTube URL with --url or as a positional argument."
        case let .missingValue(flag): return "Missing value for \(flag)."
        case let .invalidAudioFormat(value): return "Unsupported audio format: \(value). Use m4a, mp3, or opus."
        case .invalidRetries: return "--max-retries must be an integer from 0 to 10."
        case let .unknownOption(option): return "Unknown option: \(option)."
        case .multipleInputs: return "Only one YouTube URL may be provided."
        case .help: return nil
        }
    }
}
