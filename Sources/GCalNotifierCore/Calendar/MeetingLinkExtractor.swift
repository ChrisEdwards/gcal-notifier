import Foundation

/// Extracts meeting links from various event data sources.
///
/// `MeetingLinkExtractor` processes calendar event data to find video conferencing URLs,
/// prioritizing structured conference data over text extraction.
///
/// ## Extraction Priority
/// 1. `conferenceData.entryPoints[].uri` - Structured data (highest priority)
/// 2. `hangoutLink` - Legacy Google Meet
/// 3. `location` field - URL scan
/// 4. `description` field - Regex scan
/// 5. `attachments[].fileUrl` - Attachment URLs
///
/// ## Usage
/// ```swift
/// let extractor = MeetingLinkExtractor()
/// let links = extractor.extractAll(
///     conferenceEntryPoints: conferenceData?.entryPoints,
///     hangoutLink: event.hangoutLink,
///     location: event.location,
///     description: event.description,
///     attachmentURLs: attachments?.compactMap { $0.fileUrl }
/// )
/// ```
public struct MeetingLinkExtractor: Sendable {
    public init() {}

    // MARK: - Public API

    /// Extracts all meeting links from the provided sources, with deduplication.
    ///
    /// Links are extracted in priority order, with structured conference data taking precedence.
    /// Duplicate URLs are automatically removed.
    ///
    /// - Parameters:
    ///   - conferenceEntryPoints: Structured entry points from Google Calendar conferenceData.
    ///   - hangoutLink: Legacy Google Meet link.
    ///   - location: Event location field (may contain URLs).
    ///   - description: Event description field (may contain embedded URLs).
    ///   - attachmentURLs: URLs from event attachments.
    /// - Returns: Deduplicated array of meeting links.
    public func extractAll(
        conferenceEntryPoints: [ConferenceEntryPoint]? = nil,
        hangoutLink: String? = nil,
        location: String? = nil,
        description: String? = nil,
        attachmentURLs: [String]? = nil
    ) -> [MeetingLink] {
        var links: [MeetingLink] = []
        var seenURLs: Set<String> = []

        // 1. Conference data (highest priority)
        self.addConferenceLinks(from: conferenceEntryPoints, to: &links, seenURLs: &seenURLs)

        // 2. Hangout link (legacy Google Meet)
        self.addLinkIfNew(hangoutLink, to: &links, seenURLs: &seenURLs)

        // 3. Location field
        if let location {
            self.addExtractedURL(from: location, to: &links, seenURLs: &seenURLs)
        }

        // 4. Description field
        if let description {
            self.addExtractedURLs(from: description, to: &links, seenURLs: &seenURLs)
        }

        // 5. Attachment URLs
        self.addAttachmentLinks(from: attachmentURLs, to: &links, seenURLs: &seenURLs)

        return links
    }

    /// Extracts meeting links from conference entry points only.
    public func extractFromConferenceData(entryPoints: [ConferenceEntryPoint]?) -> [MeetingLink] {
        var links: [MeetingLink] = []
        var seenURLs: Set<String> = []
        self.addConferenceLinks(from: entryPoints, to: &links, seenURLs: &seenURLs)
        return links
    }

    /// Extracts a meeting link from a hangout link string.
    public func extractFromHangoutLink(_ hangoutLink: String?) -> MeetingLink? {
        guard let hangoutLink,
              let url = URL(string: hangoutLink),
              self.isValidURL(url)
        else { return nil }
        return MeetingLink(url: url)
    }

    /// Extracts meeting links from a location string.
    public func extractFromLocation(_ location: String?) -> MeetingLink? {
        guard let location else { return nil }
        guard let url = self.extractFirstMeetingURL(from: location) else { return nil }
        return MeetingLink(url: url)
    }

    /// Extracts all meeting links from a description string.
    public func extractFromDescription(_ description: String?) -> [MeetingLink] {
        guard let description else { return [] }
        return self.extractMeetingURLs(from: description).map { MeetingLink(url: $0) }
    }

    // MARK: - Private Methods

    private func addConferenceLinks(
        from entryPoints: [ConferenceEntryPoint]?,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        guard let entryPoints else { return }
        for entryPoint in entryPoints where entryPoint.entryPointType == "video" {
            self.addLinkIfNew(entryPoint.uri, to: &links, seenURLs: &seenURLs)
        }
    }

    private func addLinkIfNew(
        _ urlString: String?,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        guard let urlString,
              let url = URL(string: urlString),
              self.isValidURL(url),
              !seenURLs.contains(urlString)
        else { return }

        links.append(MeetingLink(url: url))
        seenURLs.insert(urlString)
    }

    private func addExtractedURL(
        from text: String,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        guard let url = self.extractFirstMeetingURL(from: text),
              !seenURLs.contains(url.absoluteString)
        else { return }

        links.append(MeetingLink(url: url))
        seenURLs.insert(url.absoluteString)
    }

    private func addExtractedURLs(
        from text: String,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        for url in self.extractMeetingURLs(from: text) where !seenURLs.contains(url.absoluteString) {
            links.append(MeetingLink(url: url))
            seenURLs.insert(url.absoluteString)
        }
    }

    private func addAttachmentLinks(
        from urlStrings: [String]?,
        to links: inout [MeetingLink],
        seenURLs: inout Set<String>
    ) {
        guard let urlStrings else { return }
        for urlString in urlStrings {
            guard let url = URL(string: urlString),
                  self.isMeetingURL(url),
                  !seenURLs.contains(urlString)
            else { continue }

            links.append(MeetingLink(url: url))
            seenURLs.insert(urlString)
        }
    }

    private func extractFirstMeetingURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        for match in matches {
            if let url = match.url, self.isMeetingURL(url) {
                return url
            }
        }

        return nil
    }

    private func extractMeetingURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        var seenURLs: Set<String> = []
        var urls: [URL] = []

        for match in matches {
            guard let url = match.url,
                  self.isMeetingURL(url),
                  !seenURLs.contains(url.absoluteString)
            else { continue }

            urls.append(url)
            seenURLs.insert(url.absoluteString)
        }

        return urls
    }

    private func isMeetingURL(_ url: URL) -> Bool {
        MeetingPlatform.detect(from: url) != .unknown
    }

    private func isValidURL(_ url: URL) -> Bool {
        // A valid URL must have both a scheme (http/https) and a host
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return false
        }
        return true
    }
}

// MARK: - Conference Entry Point

/// Represents a conference entry point from Google Calendar API.
public struct ConferenceEntryPoint: Codable, Sendable, Equatable {
    public let entryPointType: String
    public let uri: String?
    public let label: String?

    public init(entryPointType: String, uri: String?, label: String? = nil) {
        self.entryPointType = entryPointType
        self.uri = uri
        self.label = label
    }
}
