import AVFoundation
import GCalNotifierCore
import OSLog

// MARK: - Built-in Sounds

/// Available built-in sounds bundled with the app.
public enum BuiltInSound: String, CaseIterable, Sendable {
    case gentleChime = "gentle-chime"
    case urgentTone = "urgent-tone"
    case bell

    /// Human-readable display name for preferences UI.
    public var displayName: String {
        switch self {
        case .gentleChime: "Gentle Chime"
        case .urgentTone: "Urgent Tone"
        case .bell: "Bell"
        }
    }
}

// MARK: - Sound Validation

/// Result of validating a custom sound file.
public enum SoundValidationResult: Equatable, Sendable {
    case valid
    case fileNotFound
    case invalidFormat
    case tooLong

    /// Error message to display, or nil if valid.
    public var errorMessage: String? {
        switch self {
        case .valid: nil
        case .fileNotFound: "File not found"
        case .invalidFormat: "Unsupported audio format"
        case .tooLong: "Sound should be under 10 seconds"
        }
    }
}

// MARK: - SoundPlayer

/// Audio playback for alert sounds using AVFoundation.
///
/// Features:
/// - Built-in sounds bundled with app
/// - Custom sound file support
/// - Sound validation (format, duration)
/// - Test playback for preferences
@MainActor
public final class SoundPlayer {
    // MARK: - Singleton

    /// Shared singleton instance for app-wide sound playback.
    public static let shared = SoundPlayer()

    // MARK: - Private State

    private var player: AVAudioPlayer?

    /// Maximum allowed duration for custom sounds (10 seconds).
    private let maxSoundDuration: TimeInterval = 10.0

    // MARK: - Initialization

    /// Creates a SoundPlayer instance.
    public init() {}

    // MARK: - Playback

    /// Play a built-in sound.
    ///
    /// - Parameter sound: The built-in sound to play.
    public func play(_ sound: BuiltInSound) {
        guard let url = bundleURL(for: sound) else {
            Logger.alerts.error("Sound not found in bundle: \(sound.rawValue)")
            return
        }
        self.playFromURL(url)
    }

    /// Play a sound from a custom file path.
    ///
    /// - Parameter path: Absolute path to the sound file.
    public func playCustom(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.alerts.error("Custom sound not found: \(path)")
            return
        }
        self.playFromURL(url)
    }

    /// Play a sound by name, handling both built-in and custom sounds.
    ///
    /// - Parameters:
    ///   - name: Sound name (built-in raw value or custom identifier).
    ///   - customPath: Path to custom sound file if name doesn't match built-in.
    public func play(named name: String, customPath: String? = nil) {
        if let builtIn = BuiltInSound(rawValue: name) {
            self.play(builtIn)
        } else if let path = customPath {
            self.playCustom(path: path)
        } else {
            Logger.alerts.warning("Unknown sound name: \(name)")
        }
    }

    /// Stop any currently playing sound.
    public func stop() {
        self.player?.stop()
        self.player = nil
    }

    // MARK: - Settings Integration

    /// Play the appropriate sound for an alert stage using current settings.
    ///
    /// - Parameters:
    ///   - stage: The alert stage (stage1 or stage2).
    ///   - settings: The settings store to read sound preferences from.
    public func playAlertSound(for stage: AlertStage, settings: SettingsStore) {
        let soundName = switch stage {
        case .stage1: settings.stage1Sound
        case .stage2: settings.stage2Sound
        }

        let customPath = settings.customSoundPath
        self.play(named: soundName, customPath: customPath)
    }

    // MARK: - Test Functionality

    /// Play a built-in sound once for testing in preferences.
    ///
    /// - Parameter sound: The sound to test.
    public func testSound(_ sound: BuiltInSound) {
        self.play(sound)
    }

    /// Test a custom sound file and return whether it played successfully.
    ///
    /// - Parameter path: Path to the custom sound file.
    /// - Returns: `true` if the sound started playing, `false` otherwise.
    @discardableResult
    public func testCustomSound(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }
        self.playCustom(path: path)
        return self.player?.isPlaying ?? false
    }

    // MARK: - Validation

    /// Validate a custom sound file for use as an alert sound.
    ///
    /// - Parameter path: Path to the sound file to validate.
    /// - Returns: The validation result indicating whether the file is valid.
    public func validateCustomSound(path: String) -> SoundValidationResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            return .fileNotFound
        }

        do {
            let testPlayer = try AVAudioPlayer(contentsOf: url)
            if testPlayer.duration > self.maxSoundDuration {
                return .tooLong
            }
            return .valid
        } catch {
            Logger.alerts.debug("Sound validation failed for \(path): \(error.localizedDescription)")
            return .invalidFormat
        }
    }

    // MARK: - Private Helpers

    private func bundleURL(for sound: BuiltInSound) -> URL? {
        Bundle.main.url(
            forResource: sound.rawValue,
            withExtension: "mp3",
            subdirectory: "Sounds"
        )
    }

    private func playFromURL(_ url: URL) {
        do {
            // Stop any currently playing sound
            self.stop()

            self.player = try AVAudioPlayer(contentsOf: url)
            self.player?.volume = 1.0 // Respect system volume
            self.player?.prepareToPlay()
            self.player?.play()

            Logger.alerts.debug("Playing sound: \(url.lastPathComponent)")
        } catch {
            Logger.alerts.error("Failed to play sound: \(error.localizedDescription)")
        }
    }
}
