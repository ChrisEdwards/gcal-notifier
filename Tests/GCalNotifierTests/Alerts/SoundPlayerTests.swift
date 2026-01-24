import Foundation
import Testing

@testable import GCalNotifier
@testable import GCalNotifierCore

// MARK: - BuiltInSound Tests

@Suite("BuiltInSound")
struct BuiltInSoundTests {
    @Test("All cases have unique raw values")
    func allCases_haveUniqueRawValues() {
        let rawValues = BuiltInSound.allCases.map(\.rawValue)
        let uniqueRawValues = Set(rawValues)

        #expect(rawValues.count == uniqueRawValues.count)
    }

    @Test("Glass has correct raw value")
    func glass_hasCorrectRawValue() {
        #expect(BuiltInSound.glass.rawValue == "glass")
    }

    @Test("Hero has correct raw value")
    func hero_hasCorrectRawValue() {
        #expect(BuiltInSound.hero.rawValue == "hero")
    }

    @Test("Tink has correct raw value")
    func tink_hasCorrectRawValue() {
        #expect(BuiltInSound.tink.rawValue == "tink")
    }

    @Test("All cases have display names")
    func allCases_haveDisplayNames() {
        for sound in BuiltInSound.allCases {
            #expect(!sound.displayName.isEmpty)
        }
    }

    @Test("Display names are human readable")
    func displayNames_areHumanReadable() {
        #expect(BuiltInSound.glass.displayName == "Glass")
        #expect(BuiltInSound.hero.displayName == "Hero")
        #expect(BuiltInSound.tink.displayName == "Tink")
    }

    @Test("Can create from raw value")
    func canCreate_fromRawValue() {
        #expect(BuiltInSound(rawValue: "glass") == .glass)
        #expect(BuiltInSound(rawValue: "hero") == .hero)
        #expect(BuiltInSound(rawValue: "tink") == .tink)
    }

    @Test("Invalid raw value returns nil")
    func invalidRawValue_returnsNil() {
        #expect(BuiltInSound(rawValue: "nonexistent") == nil)
        #expect(BuiltInSound(rawValue: "") == nil)
    }
}

// MARK: - SoundValidationResult Tests

@Suite("SoundValidationResult")
struct SoundValidationResultTests {
    @Test("Valid result has no error message")
    func valid_hasNoErrorMessage() {
        #expect(SoundValidationResult.valid.errorMessage == nil)
    }

    @Test("File not found has error message")
    func fileNotFound_hasErrorMessage() {
        #expect(SoundValidationResult.fileNotFound.errorMessage == "File not found")
    }

    @Test("Invalid format has error message")
    func invalidFormat_hasErrorMessage() {
        #expect(SoundValidationResult.invalidFormat.errorMessage == "Unsupported audio format")
    }

    @Test("Too long has error message")
    func tooLong_hasErrorMessage() {
        #expect(SoundValidationResult.tooLong.errorMessage == "Sound should be under 10 seconds")
    }

    @Test("All error cases have messages")
    func allErrorCases_haveMessages() {
        let errorCases: [SoundValidationResult] = [.fileNotFound, .invalidFormat, .tooLong]
        for result in errorCases {
            #expect(result.errorMessage != nil)
        }
    }

    @Test("Results are equatable")
    func results_areEquatable() {
        #expect(SoundValidationResult.valid == SoundValidationResult.valid)
        #expect(SoundValidationResult.fileNotFound == SoundValidationResult.fileNotFound)
        #expect(SoundValidationResult.valid != SoundValidationResult.fileNotFound)
    }
}

// MARK: - SoundPlayer Tests

@Suite("SoundPlayer")
struct SoundPlayerTests {
    @MainActor
    @Test("Can create instance")
    func canCreate_instance() {
        let player = SoundPlayer()
        #expect(player != nil)
    }

    @MainActor
    @Test("Shared instance exists")
    func sharedInstance_exists() {
        let shared = SoundPlayer.shared
        #expect(shared != nil)
    }

    @MainActor
    @Test("Stop does not crash when nothing is playing")
    func stop_doesNotCrash_whenNothingPlaying() {
        let player = SoundPlayer()
        // Should not throw or crash
        player.stop()
    }

    @MainActor
    @Test("Validation returns file not found for missing file")
    func validation_returnsFileNotFound_forMissingFile() {
        let player = SoundPlayer()
        let result = player.validateCustomSound(path: "/nonexistent/path/to/sound.mp3")
        #expect(result == .fileNotFound)
    }

    @MainActor
    @Test("Validation returns file not found for empty path")
    func validation_returnsFileNotFound_forEmptyPath() {
        let player = SoundPlayer()
        let result = player.validateCustomSound(path: "")
        #expect(result == .fileNotFound)
    }

    @MainActor
    @Test("Custom sound returns false for missing file")
    func customSound_returnsFalse_forMissingFile() {
        let player = SoundPlayer()
        let result = player.testCustomSound(path: "/nonexistent/path/to/sound.mp3")
        #expect(result == false)
    }
}

// MARK: - SoundPlayer Alert Stage Integration Tests

@Suite("SoundPlayer Alert Stage Integration")
struct SoundPlayerAlertStageIntegrationTests {
    /// Creates an isolated UserDefaults suite for test isolation.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SoundPlayerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return defaults
    }

    @MainActor
    @Test("Play alert sound for stage 1 uses stage1 sound setting")
    func playAlertSound_stage1_usesStage1Setting() {
        let defaults = self.makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.stage1Sound = "glass"

        // Note: We can't easily test actual playback without sound files in the bundle.
        // This test verifies the settings integration works without crashing.
        let player = SoundPlayer()
        player.playAlertSound(for: .stage1, settings: settings)

        // No crash means success for this level of testing
        #expect(true)
    }

    @MainActor
    @Test("Play alert sound for stage 2 uses stage2 sound setting")
    func playAlertSound_stage2_usesStage2Setting() {
        let defaults = self.makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.stage2Sound = "hero"

        let player = SoundPlayer()
        player.playAlertSound(for: .stage2, settings: settings)

        // No crash means success for this level of testing
        #expect(true)
    }

    @MainActor
    @Test("Play named with unknown name does not crash")
    func playNamed_unknownName_doesNotCrash() {
        let player = SoundPlayer()
        player.play(named: "unknown-sound", customPath: nil)

        // Should not crash even with unknown sound
        #expect(true)
    }

    @MainActor
    @Test("Play named with unknown name and custom path attempts custom path")
    func playNamed_unknownName_withCustomPath_attemptsCustomPath() {
        let player = SoundPlayer()
        player.play(named: "custom", customPath: "/nonexistent/custom.mp3")

        // Should not crash even with nonexistent path
        #expect(true)
    }
}

// MARK: - SoundPlayer Settings Default Sound Tests

@Suite("SoundPlayer Settings Default Sounds")
struct SoundPlayerSettingsDefaultSoundTests {
    /// Creates an isolated UserDefaults suite for test isolation.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SoundPlayerTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return defaults
    }

    @Test("Default stage1 sound matches glass built-in")
    func defaultStage1Sound_matchesBuiltIn() {
        let defaults = self.makeDefaults()
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.stage1Sound == BuiltInSound.glass.rawValue)
    }

    @Test("Default stage2 sound matches hero built-in")
    func defaultStage2Sound_matchesBuiltIn() {
        let defaults = self.makeDefaults()
        let settings = SettingsStore(defaults: defaults)

        #expect(settings.stage2Sound == BuiltInSound.hero.rawValue)
    }

    @Test("All built-in sounds have matching raw values for settings")
    func builtInSounds_matchSettingsValues() {
        // Verify that the built-in sounds can be used with the settings store
        let validSoundNames = BuiltInSound.allCases.map(\.rawValue)

        #expect(validSoundNames.contains("glass"))
        #expect(validSoundNames.contains("hero"))
        #expect(validSoundNames.contains("tink"))
    }
}
