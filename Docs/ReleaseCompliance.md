# Farport release compliance audit — 2026-11-13

This audit describes code and proposed answers. It does not submit legal declarations,
change store availability, publish App Privacy or certify compliance for the owner.

## Encryption

FarportSSH → vendored Citadel → swift-nio-ssh / swift-crypto includes SSH transport
and SFTP, password/public-key authentication and standard cryptographic algorithms.
Swift Crypto includes BoringSSL; this is **not limited to Apple's built-in HTTPS**.
`Package.resolved` pins the exact dependencies. Source app Info.plists have no
`ITSAppUsesNonExemptEncryption=false`; the release scripts do not add it.

Apple requires the owner to determine export requirements for encryption, including
standard algorithms supplied outside the OS. Apple's current documentation calls
for a French encryption declaration for that case if distributing in France.
The owner must determine applicable exemptions/classification and any reporting or
ANSSI documentation, upload required documents in ASC, and associate an approved
App Encryption Declaration/code with the exact build when applicable. Do not disable
France or copy the game's `false` answer as a shortcut.

The owner reported on November 13 that no declaration had apparently been prepared.
The workflow can sign/upload while the owner resolves this, but cannot finish its
review stage while Apple's exact build has unanswered encryption compliance. If the
build says non-exempt, it requires an APPROVED declaration belonging to Farport.
An existing `false` answer is reported as an **owner answer**, not independently
certified by the script. The script never silently reuses a prior build's answer.

Sources checked:
- [Apple: export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [Apple: documentation by encryption type](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
- [Apple: determine and upload documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)

## Data handling and privacy manifests

First-party code has no advertising/tracking SDK, developer analytics endpoint,
Farport account/backend or automatic developer crash uploader. SSH/SFTP goes to
user-chosen servers. Credentials/server pins remain in Keychain; terminal content
remains local memory. Optional CloudKit stores encrypted host profile/tab definitions
in the user's **private** database, not the developer's public database. Secrets,
terminal output and files are not CloudKit payloads. Inspect `FarportCloud` and
[the policy](../AppStore/privacy-policy.md) before changing any disclosure.

Apple defines collection by off-device transfer accessible to the developer/partners
beyond request servicing. Private CloudKit databases are user-accessible by default,
not visible as developer portal data. These facts support considering a no-developer-
collection label, but a CloudKit feature is not the same as the game's entirely local
storage. The owner must review the actual service relationships, support email and
privacy answers. The workflow deliberately **does not publish a Data Not Collected
answer**. Support email is external, optional, and must not include secrets.

New app manifests (macOS/iOS) contain:
- No tracking/domains and no developer-collected data categories, matching the above
  audited code; this is a bundle declaration, not a substitute for ASC App Privacy.
- UserDefaults **CA92.1**: device-local terminal preferences (`SharedUI/TerminalAppearanceSettings.swift`).
- File timestamps **C617.1 / 3B52.1**: app/group container metadata and user-selected
  files. First-party file import/export plus stat/fstat in the statically linked
  SwiftTerm Kitty file path inspect local file information. Remote SFTP timestamps
  are protocol data, not themselves a local required-reason API use.
- Finder's separate manifest declares file access reasons; it does not use the UI
  terminal UserDefaults. SwiftNIO/Swift Crypto dependency manifests remain bundled
  by their packages, never removed/replaced by this app manifest.

No disk-space, active-keyboard or device-uptime reason is added speculatively.
CI verifies the copied app/extension manifests against these source manifests.
Re-audit when dependencies, telemetry, persistence or API usage changes.

Sources checked:
- [Apple App Privacy details and collection definition](https://developer.apple.com/app-store/app-privacy-details/)
- [Private CloudKit database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)

## Age rating

Farport is a developer tool, not Games/Puzzle. It contains no ads, purchases,
loot boxes, gambling, health advice, social feed or bundled mature/violent material.
No Kids Category or numerical age override is chosen by automation.

A terminal displays arbitrary remote content, may run remote text browsers/chat
programs, and Mac SFTP opens selected remote files externally. That makes three
answers worth explicit owner assessment: unrestrictedWebAccess, messagingAndChat,
userGeneratedContent. Farport has no embedded WKWebView/browser or built-in chat
service; external URL opening is separate. The owner's existing Apple answers are
reused when present; absent answers are an actionable gate rather than guessed false.
All other fields in release.json are based on the application's built-in content.
The complete questionnaire (including socialMediaAgeRestricted) is read back, and
Apple computes the final rating. Shared reviewed/live answers are never edited.

[Apple age ratings and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)

## Other owner gates

- Pricing, territories, DSA/trader status, agreements and Content Rights remain
  owner's decisions. A remote content client must not copy a game's rights declaration.
- Production CloudKit deployment is not provisioning: confirm deployed `HarborHost`
  / encrypted `profile` schema and test distribution sync on controlled accounts.
- Owner explicitly approved keeping current Icon Composer artwork on November 13.
- Existing screenshots are from November 1–2. Host/default/tab-mode controls changed
  since capture. No automatic recapture or UI tests are part of release automation.
- Published Bandit/Rebex credentials cover SSH/read-only SFTP, not writable SFTP,
  ProxyJump or tmux. Neither external server is operated or guaranteed by Farport.
- Distribution resource/signature checks do not replace manual Local Network,
  server-key trust, Keychain, Finder writes and cloud conflict testing.
