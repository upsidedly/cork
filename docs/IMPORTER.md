# Cork Importer

Open **Import from Pinterest…** from Cork's toolbar, File menu, menu-bar menu or welcome screen. Cork Importer is bundled under `Cork.app/Contents/Helpers`; its executable is `cork-importer`. It does not require an agent, MCP client, browser extension, Python, or a developer account.

## Connect and choose

Sign in to Pinterest in a supported browser. Choose the exact browser profile in the importer. Read the disclosure and tick its consent checkbox before connecting. A successful connection verifies Pinterest's signed-in account identity before listing boards.

If macOS protects the browser's folder and automatic discovery finds no readable profiles, use **Choose Profile Folder… → your browser**. Select its `Default`/`Profile 1` folder, or Firefox profile, in the macOS file picker. That grants access only through your deliberate folder selection; Cork does not request Full Disk Access. A separate Safe Storage prompt can still be needed for decryption.

Select boards and a quota for each: **20** by default, **50**, **100**, **150**, **200**, or **All**. All follows paginated feeds rather than assuming the first page is complete. Repeated cursors, capacity limits and early feed endings are shown in Import details. Pinterest may return fewer pins than its board count. Videos, unsupported image formats and unrelated recommendations are skipped.

Review the gallery. Each image has a Remove/Restore button. Filter by source board, Keep All/Remove All within that filter, and turn on Show removed to recover discarded choices. Only keepers download at full size. **Create a collage after import** is optional; an existing wall is otherwise unchanged.

## Daily Pinterest sync

After connecting and selecting boards, choose **Keep Selected Boards Fresh Daily…**. Set the local check time (9 AM by default), choose up to **5, 10 or 20 new images per day** (10 by default), read the recurring-access disclosure and tick its initially unchecked consent box. Cork and its bundled importer must be installed in Applications.

The first check records the latest 100 image pins per selected board as a baseline. It downloads none of those older pins. Later checks inspect that recent window and queue genuinely new pin IDs. This is a bounded recent-feed check, not a complete change archive: pins outside the newest 100 image entries between checks can be missed. Pinterest video pins are skipped.

New images get the same local colour measurements, source-board identity, aspect ratio and mood metadata as a manual import. Sources take turns within the daily limit, with the first source rotating between checks. Existing Cork pin URLs are reconciled before importing; rejected pin IDs stay excluded. New images join future dice rolls without an app rebuild. The visible collage is never rolled automatically by the importer.

Daily sync has a **32 MB image-download budget per local day** and stops downloads below **2 GB free space**. Transfer attempts reserve their allowance before network access; a failed or interrupted response conservatively consumes that reservation until the next day. **Check Now** respects both daily limits. The queue holds at most 2,000 pin metadata records, and seen/excluded histories are bounded to 100,000 IDs. No full-resolution archive is retained.

**Daily Sync…** shows the saved boards, last check and result. **Pause** removes the scheduled job while retaining the connection for Resume. **Remove Connection** also removes the profile bookmark, account name and recurring consent; previously imported images and exclusions remain. Choose Boards returns to the normal connection flow for changing sources. Manual gallery Remove/Restore decisions also update daily exclusions.

macOS runs the opt-in job through `~/Library/LaunchAgents/dev.upsided.cork-importer.daily.plist`. A missed calendar check coalesces after wake. The job can open Cork in the background to receive images; it does not open the library. A run is limited to five minutes and concurrent runs are rejected. Automatic checks run at most once per local day, including after a failed check; Check Now is an explicit retry.

Recurring access is separate from one-time import consent. Only a read-only security-scoped profile-folder bookmark and source choices are remembered. Each check rereads Pinterest cookie rows and uses an in-memory session. No cookies or browser keys are saved. Background Safe Storage reads disallow interactive authentication; denied/expired access stops the check and reports a reconnect message instead of showing a password prompt. The next check can use a renewed browser session. Daily metadata lives separately in the private `Cork Importer/Daily` folder, so a background run cannot discard a manual review.

The bundled executable also accepts `--daily-status` (counts and status), `--daily-sync` (scheduled check), `--daily-now` (explicit check) and repeated `--exclude-pin ID` arguments. These commands do not grant access or enable an unconfigured connection.

## Browser privacy

- Profile discovery looks for supported cookie-store paths; it does not read cookie values or Keychain secrets.
- Connection opens the selected SQLite database read-only and selects Pinterest domains only. Partitioned/container cookies are excluded. No database copy is made.
- Chrome, Chromium, Brave and Edge normally encrypt cookies with a macOS Safe Storage key. macOS may ask whether Cork Importer may read that key. The key can decrypt that browser's cookies; this app only decrypts rows already scoped to Pinterest. It never creates a missing key.
- Firefox's regular-profile Pinterest cookies are read without a Safe Storage request. Safari is unsupported; no Full Disk Access is requested.
- The account must have a valid `_pinterest_sess` cookie, and Pinterest must independently confirm an authenticated identity. Unsupported encryption, denied access and expired sessions fail visibly.
- Browser credentials stay in memory, are never included in a review/manifest, and clear on disconnect or quit. Only HTTPS Pinterest hosts receive cookie headers. Redirects outside Pinterest are refused. Image CDN requests use a separate session without credentials.
- Neither app uploads images to a Cork backend. There is no backend, analytics or telemetry. Pinterest still receives the requests needed for importing.

You can cancel macOS's key request. Open Pinterest in the chosen profile to renew an expired session. Cork does not solve CAPTCHAs or bypass service limits. The importer uses Pinterest website resource endpoints rather than its official OAuth API; it is independent of Pinterest and may need updates when the website changes. Respect source media rights and applicable service terms.

## Storage and recovery

The review contains original pin links, source board IDs/names, image URLs and keep/remove decisions in a private `review.json` under `~/Library/Application Support/Cork Importer` (directory `0700`, file `0600`). No cookies or keys are serialized. A new review replaces an earlier review only through the app's explicit review/discard flow.

Previews are lazy and kept in a 12 MB memory cache. Full keepers are downloaded in batches of ten, bounded to 32 MB/100 megapixels per source, normalized to at most 2,048 pixels for collage use, then copied into Cork's owned library. Measured pixel coverage, palettes, source identity, aspect ratios and mood assignments are saved with each image. Cork recomputes classification from its owned copy. These collage images are not automatically promoted to wallpapers: wallpaper eligibility still requires real native-size pixels.

Staging is removed after every completed/failed batch and at importer startup/quit. The importer pauses when less than 1 GB remains. It supports up to 20,000 images per review/library, with smaller practical limits determined by disk space. The gallery shows a rough storage estimate before full downloads. No original-resolution archive is retained in addition to Cork's copy.

Stop or quit to interrupt. The review and confirmed progress remain. Resume Review then Add to Cork reconciles stable IDs and original pin URLs with Cork before writing again. A lost reply after a commit never causes an automatic mutation replay. Existing library images are reused. Discard Review removes the private review/staging, while images already committed in Cork remain there.

## Protocol references

The original Swift implementation follows observed Pinterest resource formats and Chromium's documented cookie storage behavior. No gallery-dl, Übersicht, PinMark or plugin source is bundled.

- [Pinterest OAuth setup](https://dev.pinterest.com/docs/getting-started/set-up-authentication-and-authorization/) explains the official API's registered-app route.
- [gallery-dl's Pinterest extractor](https://github.com/mikf/gallery-dl/blob/master/gallery_dl/extractor/pinterest.py) documents resource names/options used by Pinterest's website; consulted for protocol facts only, without copying its GPL-2.0-only source.
- [Chromium macOS key provider](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/os_crypt/async/browser/keychain_key_provider.mm) defines the native v10/PBKDF2/AES-CBC format.
- [Chromium Keychain names](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/os_crypt/common/keychain_password_mac.mm) and [cookie domain hashes](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/net/extras/sqlite/sqlite_persistent_cookie_store.cc) support key lookup and v24 domain-integrity verification.
