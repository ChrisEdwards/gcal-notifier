# Design Feedback (Codex 52)

- **Data layer resilience**: Add `SyncEngine` with syncToken/ETag incremental fetches plus `EventStore` cache in Application Support to survive offline/wake and cut rate limits; jittered polling with exponential backoff.
- **Alert experience**: Keep two-stage alerts but add per-stage snooze, optional repeat escalation inside the 2-minute window, and DND-aware fallback to Notification Center; badge when suppressed.
- **Link extraction accuracy**: Include attachments URLs, canonicalize/deduplicate meeting links, and extend keyword filtering to `location`; when overlaps occur, prioritize link-bearing earliest event while surfacing secondary conflicts.
- **Diagnostics and self-healing**: Settings diagnostics panel (last sync, next poll, token expiry, cache age, last error) plus “Force full sync”; structured logs to `~/Library/Logs/gcal-notifier/`.
- **Security hardening**: Use calendar.readonly scope, keep client secret/token only in Keychain (no disk copies); enable hardened runtime + App Sandbox (network/keychain only).
- **Implementation order tweak**: Finish auth + storage first, then sync engine/cache, then settings UI (with diagnostics), then menu bar UI and alerts; UI rides on the stabilized data layer.
