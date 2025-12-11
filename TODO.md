# Project TODO

## Environment & Config
- [x] Create `robot.yaml` with required RPA libraries (Email, Google, PDF, Browser, FileSystem, optional Dialogs/Notifier).
- [x] Document environment variables/credentials (Gmail app passwords, Drive folder ID, Athena mock creds) in README guidance.

## Email Intake Automation
- [x] Configure `RPA.Email.ImapSmtp` connection for dedicated Gmail intake inbox (multi-inbox expansion still pending credentials).
- [x] Implement polling keyword to download new PDF attachments from the configured inbox.
- [ ] Log processed message IDs to avoid duplicate handling.

## Google Drive Intake Folder
- [x] Configure `RPA.Google` and authenticate to Drive via service account JSON.
- [x] Poll "Patient Intake Uploads" folder for new PDFs.
- [x] Implement move/rename helpers for Archive and Exceptions folders.

## PDF Parsing
- [x] Use `RPA.PDF` (or helper Python) to extract required fields (First/Last Name, DOB -> MM/DD/YYYY, Phone, Email, Insurance, Member ID, Referring Physician).
- [x] Add regex/heuristics plus confidence checks; fail when extraction below 95%.

## Browser Automation
- [x] Launch local `mock_athena.html` via local HTTP server (port 8000).
- [x] Automate login with mock credentials via `RPA.Browser.Selenium`.
- [x] Fill intake form with parsed data and upload PDF before submitting.

## File Archiving & Exceptions
- [x] Rename PDFs to `LastName_FirstName_DOBMMDDYYYY.pdf` after successful processing.
- [x] Move successful files into Drive `Archived` subfolder.
- [x] Move failed/exception files into Drive `Exceptions` subfolder and capture reason.

## Notifications & Error Handling
- [x] Send SMTP alert to `alex@westsidebilling.com` for each exception with context.
- [ ] Implement retries for transient errors beyond the current structured logging.

## Documentation & Deployment
- [x] Write `README.md` with setup, `rcc run`, `rcc cloud push`, scheduling, and GitHub push instructions.
- [x] Include `mock_athena.html`, helper modules, and optional `requirements.txt`.
- [ ] Test locally with `robot tasks.robot` (or `rcc run`) and capture/document run results.
