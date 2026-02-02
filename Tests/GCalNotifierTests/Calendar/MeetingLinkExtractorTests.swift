import Foundation
import Testing
@testable import GCalNotifierCore

@Suite("MeetingLinkExtractor Tests")
struct MeetingLinkExtractorTests {
    let extractor = MeetingLinkExtractor()

    // MARK: - Conference Data Extraction

    @Test("Extract from conference data - Google Meet")
    func extractFromConferenceData_googleMeet() {
        let entryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/abc-defg-hij"),
        ]

        let links = self.extractor.extractFromConferenceData(entryPoints: entryPoints)

        #expect(links.count == 1)
        #expect(links.first?.platform == .googleMeet)
        #expect(links.first?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Extract from conference data - Zoom")
    func extractFromConferenceData_zoom() {
        let entryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: "https://zoom.us/j/123456789"),
        ]

        let links = self.extractor.extractFromConferenceData(entryPoints: entryPoints)

        #expect(links.count == 1)
        #expect(links.first?.platform == .zoom)
    }

    @Test("Extract from conference data - ignores phone entry points")
    func extract_phoneEntryPoint_ignored() {
        let entryPoints = [
            ConferenceEntryPoint(entryPointType: "phone", uri: "tel:+1-555-123-4567"),
            ConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/abc-defg-hij"),
        ]

        let links = self.extractor.extractFromConferenceData(entryPoints: entryPoints)

        #expect(links.count == 1)
        #expect(links.first?.platform == .googleMeet)
    }

    @Test("Extract from conference data - nil entry points")
    func extractFromConferenceData_nil() {
        let links = self.extractor.extractFromConferenceData(entryPoints: nil)
        #expect(links.isEmpty)
    }

    @Test("Extract from conference data - empty entry points")
    func extractFromConferenceData_empty() {
        let links = self.extractor.extractFromConferenceData(entryPoints: [])
        #expect(links.isEmpty)
    }

    // MARK: - Hangout Link Extraction

    @Test("Extract from hangout link")
    func extractFromHangoutLink() {
        let link = self.extractor.extractFromHangoutLink("https://meet.google.com/xyz-uvwx-abc")

        #expect(link != nil)
        #expect(link?.platform == .googleMeet)
    }

    @Test("Extract from hangout link - nil")
    func extractFromHangoutLink_nil() {
        let link = self.extractor.extractFromHangoutLink(nil)
        #expect(link == nil)
    }

    @Test("Extract from hangout link - invalid URL")
    func extractFromHangoutLink_invalidURL() {
        let link = self.extractor.extractFromHangoutLink("not a valid url")
        #expect(link == nil)
    }

    // MARK: - Location Field Extraction

    @Test("Extract from location - meet link")
    func extractFromLocation_meetLink() {
        let location = "https://meet.google.com/abc-defg-hij"
        let link = self.extractor.extractFromLocation(location)

        #expect(link != nil)
        #expect(link?.platform == .googleMeet)
    }

    @Test("Extract from location - physical address (no link)")
    func extractFromLocation_physicalAddress_noLink() {
        let location = "123 Main Street, San Francisco, CA 94102"
        let link = self.extractor.extractFromLocation(location)

        #expect(link == nil)
    }

    @Test("Extract from location - mixed text with link")
    func extractFromLocation_mixedTextWithLink() {
        let location = "Conference Room A or https://zoom.us/j/123456789"
        let link = self.extractor.extractFromLocation(location)

        #expect(link != nil)
        #expect(link?.platform == .zoom)
    }

    @Test("Extract from location - nil")
    func extractFromLocation_nil() {
        let link = self.extractor.extractFromLocation(nil)
        #expect(link == nil)
    }

    @Test("Extract from location - non-meeting URL ignored")
    func extractFromLocation_nonMeetingURL() {
        let location = "https://example.com/some-page"
        let link = self.extractor.extractFromLocation(location)

        #expect(link == nil)
    }

    // MARK: - Description Field Extraction

    @Test("Extract from description - embedded link")
    func extractFromDescription_embeddedLink() {
        let description = "Join us for the meeting! Link: https://teams.microsoft.com/l/meetup-join/abc"
        let links = self.extractor.extractFromDescription(description)

        #expect(links.count == 1)
        #expect(links.first?.platform == .teams)
    }

    @Test("Extract from description - multiple links deduplicates")
    func extractFromDescription_multipleLinks_deduplicates() {
        // Note: NSDataDetector normalizes URLs, so we use exactly the same URL string for duplicates
        let meetLink = "https://meet.google.com/abc-defg-hij"
        let zoomLink = "https://zoom.us/j/123456789"
        let description = "Primary: \(meetLink) Backup: \(zoomLink) Repeated: \(meetLink)"
        let links = self.extractor.extractFromDescription(description)

        #expect(links.count == 2)
        #expect(links[0].platform == .googleMeet)
        #expect(links[1].platform == .zoom)
    }

    @Test("Extract from description - nil")
    func extractFromDescription_nil() {
        let links = self.extractor.extractFromDescription(nil)
        #expect(links.isEmpty)
    }

    @Test("Extract from description - no meeting links")
    func extractFromDescription_noMeetingLinks() {
        let description = "Please review the document at https://docs.google.com/document/d/abc123"
        let links = self.extractor.extractFromDescription(description)

        #expect(links.isEmpty)
    }

    // MARK: - Platform Detection

    @Test("Platform detection - all platforms")
    func platformDetection_allPlatforms() {
        let testCases: [(String, MeetingPlatform)] = [
            ("https://meet.google.com/abc-defg-hij", .googleMeet),
            ("https://zoom.us/j/123456789", .zoom),
            ("https://zoomgov.com/j/123456789", .zoom),
            ("https://teams.microsoft.com/l/meetup-join/abc", .teams),
            ("https://teams.live.com/meet/abc", .teams),
            ("https://example.webex.com/meet/abc", .webex),
            ("https://app.slack.com/huddle/T123/C456", .slackHuddle),
        ]

        for (urlString, expectedPlatform) in testCases {
            let entryPoints = [ConferenceEntryPoint(entryPointType: "video", uri: urlString)]
            let links = self.extractor.extractFromConferenceData(entryPoints: entryPoints)

            #expect(links.count == 1, "Failed for URL: \(urlString)")
            #expect(links.first?.platform == expectedPlatform, "Failed for URL: \(urlString)")
        }
    }

    // MARK: - Full Extraction (extractAll)

    @Test("Extract all - conference data takes priority")
    func extractAll_conferenceDataTakesPriority() {
        let conferenceEntryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/abc-defg-hij"),
        ]
        let hangoutLink = "https://meet.google.com/abc-defg-hij"
        let location = "https://meet.google.com/abc-defg-hij"

        let links = self.extractor.extractAll(
            conferenceEntryPoints: conferenceEntryPoints,
            hangoutLink: hangoutLink,
            location: location
        )

        // Should deduplicate to just one link
        #expect(links.count == 1)
        #expect(links.first?.platform == .googleMeet)
    }

    @Test("Extract all - collects from all sources")
    func extractAll_collectsFromAllSources() {
        let conferenceEntryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/conf-data"),
        ]
        let hangoutLink = "https://meet.google.com/hangout-link"
        let location = "https://zoom.us/j/location123"
        let description = "Join via https://teams.microsoft.com/l/meetup-join/desc"
        let attachmentURLs = ["https://example.webex.com/meet/attachment"]

        let links = self.extractor.extractAll(
            conferenceEntryPoints: conferenceEntryPoints,
            hangoutLink: hangoutLink,
            location: location,
            description: description,
            attachmentURLs: attachmentURLs
        )

        #expect(links.count == 5)
        #expect(links[0].url.absoluteString == "https://meet.google.com/conf-data")
        #expect(links[1].url.absoluteString == "https://meet.google.com/hangout-link")
        #expect(links[2].url.absoluteString == "https://zoom.us/j/location123")
        #expect(links[3].url.absoluteString == "https://teams.microsoft.com/l/meetup-join/desc")
        #expect(links[4].url.absoluteString == "https://example.webex.com/meet/attachment")
    }

    @Test("Extract all - empty sources")
    func extractAll_emptySources() {
        let links = self.extractor.extractAll()
        #expect(links.isEmpty)
    }

    @Test("Extract all - attachment with non-meeting URL ignored")
    func extractAll_attachmentNonMeetingURL() {
        let attachmentURLs = ["https://docs.google.com/document/d/abc"]

        let links = self.extractor.extractAll(attachmentURLs: attachmentURLs)

        #expect(links.isEmpty)
    }

    @Test("Extract all - deduplication across sources")
    func extractAll_deduplicationAcrossSources() {
        let sharedURL = "https://meet.google.com/abc-defg-hij"
        let conferenceEntryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: sharedURL),
        ]
        let hangoutLink = sharedURL
        let description = "Join: \(sharedURL)"

        let links = self.extractor.extractAll(
            conferenceEntryPoints: conferenceEntryPoints,
            hangoutLink: hangoutLink,
            description: description
        )

        #expect(links.count == 1)
    }

    // MARK: - Edge Cases

    @Test("Extract handles malformed URLs gracefully")
    func extractHandlesMalformedURLs() {
        let entryPoints = [
            ConferenceEntryPoint(entryPointType: "video", uri: ""),
            ConferenceEntryPoint(entryPointType: "video", uri: nil),
            ConferenceEntryPoint(entryPointType: "video", uri: "not a url at all"),
        ]

        let links = self.extractor.extractFromConferenceData(entryPoints: entryPoints)

        #expect(links.isEmpty)
    }

    @Test("Extract skips invalid URLs gracefully")
    func extractSkipsInvalidURLs() {
        let description = "Invalid: ://missing-scheme.com and valid: https://meet.google.com/abc-defg-hij"
        let links = self.extractor.extractFromDescription(description)

        // NSDataDetector should only find the valid URL
        #expect(links.count == 1)
        #expect(links.first?.platform == .googleMeet)
    }
}

// MARK: - ConferenceEntryPoint Tests

@Suite("ConferenceEntryPoint Tests")
struct ConferenceEntryPointTests {
    @Test("Init creates valid entry point")
    func initCreatesValidEntryPoint() {
        let entryPoint = ConferenceEntryPoint(
            entryPointType: "video",
            uri: "https://meet.google.com/abc",
            label: "Google Meet"
        )

        #expect(entryPoint.entryPointType == "video")
        #expect(entryPoint.uri == "https://meet.google.com/abc")
        #expect(entryPoint.label == "Google Meet")
    }

    @Test("Codable round trip")
    func codableRoundTrip() throws {
        let original = ConferenceEntryPoint(
            entryPointType: "video",
            uri: "https://zoom.us/j/123",
            label: "Zoom"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConferenceEntryPoint.self, from: encoded)

        #expect(decoded == original)
    }
}
