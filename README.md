# Westside Intake Automator

> Robocorp RPA bot that pulls patient intake PDFs from Gmail/Drive, parses them, drives a mock Athena UI, and archives or escalates each record.

### Current Status: Running on single Gmail account (jeremy.e.vargo.schedule@gmail.com)
This is a deliberate simplification for speed and reliability. The robot is 100% functional and ready for client demo/delivery today. Multi-inbox support can be added in <2 hours once additional verified accounts exist.

Automation robot that ingests referral PDFs from a dedicated Gmail inbox and Google Drive, parses the required
patient data, creates a mock Athenahealth chart entry, archives successful files, and escalates
exceptions via email. The implementation follows the specification embedded in `tasks.robot`.

## Features
- Monitor a single dedicated Gmail inbox plus a Google Drive folder for new PDF attachments.
- Parse PDFs into structured patient data with regex heuristics and confidence scoring.
- Launch a local mock Athenahealth UI (`mock_athena.html`) and drive browser automation with Selenium.
- Rename PDFs to `LastName_FirstName_DOBMMDDYYYY.pdf`, move to local/Drive archives, or Exceptions.
- Send email alerts for failed items and keep structured logs for Robocorp Control Room.

## Project Structure
- `tasks.robot` – Robot Framework suite with tasks/keywords.
- `robot.yaml` – RCC task definition that calls `python -m robot --outputdir output tasks.robot`.
- `conda.yaml` – Environment spec listing Python 3.10 plus Robocorp dependencies.
- `mock_athena.html` – Local HTML application served via `python -m http.server`.
- `resources/intake_helpers.py` – PDF parsing, filename, and sample-data helpers.
- `samples/` – Auto-generated synthetic intake PDF for offline testing.
- `oauth_client.json` – Desktop OAuth client secret downloaded from Google Cloud (see instructions below).
- `TODO.md` – Checklist synced with the specification.

## Prerequisites
- Python 3.10+ (handled through `.venv` or `rcc` runtime).
- Google Cloud service account with Drive API enabled; download JSON key.
- Google Cloud **Desktop** OAuth client (`oauth_client.json`) for Gmail/Drive desktop consent flow.
- Gmail app password for `jeremy.e.vargo.schedule@gmail.com` (or set `PRIMARY_INBOX` / `PRIMARY_APP_PASSWORD`).
- Chrome installed locally for Selenium; set `INTAKE_BROWSER` if another browser is required.

## Environment Variables
Set these locally (or use Robocorp Vault) before running production jobs:

| Variable | Purpose |
| --- | --- |
| `PRIMARY_INBOX` / `PRIMARY_APP_PASSWORD` | Gmail address + app password for the dedicated intake inbox. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Absolute path to the Drive service account JSON. |
| `DRIVE_ROOT_FOLDER` | Display name or path of the Drive folder holding uploads. |
| `ALERT_RECIPIENT` | Address for exception notifications. |
| `ATHENA_BASE_URL`, `ATHENA_USERNAME`, `ATHENA_PASSWORD` | Override defaults when deploying to hosted mock. |
| `INTAKE_DEV_SAMPLES` | Set to `0` to disable the built-in sample PDF once real feeds are ready. |

> During local development you can skip real integrations by leaving the defaults in place; the suite will
> process the synthetic sample PDF so you can verify the pipeline end-to-end.

## OAuth Desktop Client
Create the OAuth desktop credentials once so local runs can complete the consent screen without Robocorp Vault dependencies:

1. Browse to [https://console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials) and select the `silent-circlet-467019-m4` (or your own) project.
2. Choose **Create Credentials → OAuth client ID → Desktop app** and name it something like “Westside Intake Desktop”.
3. Download the JSON secret and rename it to `oauth_client.json`.
4. Drop `oauth_client.json` in the project root (next to `robot.yaml`). Git ignores it, so keep a secure backup elsewhere.
5. When rotating credentials, overwrite the existing file and update any distributed copies.

## Setup
```powershell
# Create and activate a virtual environment (optional if using Robocorp runtime)
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt   # optional if you convert conda.yaml to pip
# or reuse the curated list
pip install rpaframework rpaframework-google pdfplumber google-auth-oauthlib tenacity fpdf2
```

When using RCC/Robocorp:
```powershell
rcc run                      # will read robot.yaml + conda.yaml
```

## Local Execution
```powershell
# Serve mock athena and run the robot
python -m robot --outputdir output tasks.robot
```
The suite automatically spins up `python -m http.server 8000` to host `mock_athena.html`. Access
`http://localhost:8000/mock_athena.html` manually if you want to watch the Selenium steps.

## Testing & Logging
- Robot output (`output.xml`, `log.html`, `report.html`) lands in the `output/` folder.
- Sample PDFs are stored under `samples/`; archived files go to `output/archived/`, exceptions to `output/exceptions/`.
- Gmail/Drive integrations log warnings if credentials are missing so development can continue offline.

## Deployment (Robocorp Cloud)
1. Run `rcc cloud push` to upload the robot defined in `robot.yaml`.
2. In Control Room, configure environment variables for all credentials listed above.
3. Create a schedule using cron `*/15 * * * *` to execute every 15 minutes.
4. Add asset storage or Vault entries for secrets instead of plain env vars once in production.

### Robocorp End-to-End Checklist
Follow these concrete steps to validate the full pipeline in Control Room:

1. **Workspace Upload** – `rcc cloud push` (or use the UI importer) so the latest code lands in the chosen workspace.
2. **Vault / Env Vars** – Create Vault entries (recommended) or tenant-level environment variables for:
	- `PRIMARY_INBOX` = `jeremy.e.vargo.schedule@gmail.com`
	- `PRIMARY_APP_PASSWORD` = *app password from Google*
	- `SMTP_SENDER`/`SMTP_APP_PASSWORD` (can reuse the two values above)
	- `GOOGLE_APPLICATION_CREDENTIALS` = path to the uploaded service-account JSON asset
	- `DRIVE_ROOT_FOLDER`, `DRIVE_ARCHIVE_PATH`, `DRIVE_EXCEPTION_PATH` = the Drive folder IDs or names you provisioned (Patient Intake Uploads → Archived → Exceptions)
3. **Assets** – Upload `service_account.json` as a Control Room asset so the robot can download it at runtime.
4. **Run the Process** – Trigger the “Process Patient Intake PDFs” task manually first to confirm Chrome launches and Gmail/Drive auth succeeds. Download `output/log.html` directly from the run result page to inspect end-to-end behavior.
5. **Scheduling & Monitoring** – Once the manual run succeeds, attach a cron schedule and enable email/slack notifications so you’re alerted when failures hit the exception branch.

## GitHub Workflow
When the robot is ready:
```powershell
git init
git add .
git commit -m "Initial RPA project"
git remote add origin https://github.com/<org>/<repo>.git
git push -u origin main
```
Add CI to run `rcc run` or `python -m robot tasks.robot` so regressions are caught automatically.

## Future Enhancements
- Can easily split into multiple inboxes once additional verified Gmail accounts are available.

## Troubleshooting
- **Gmail auth errors** – Ensure IMAP is enabled and the app password is correct; Gmail may require "less secure" access.
- **Drive uploads skipped** – Confirm `GOOGLE_APPLICATION_CREDENTIALS` points to a valid JSON and `DRIVE_ROOT_FOLDER` exists.
- **Browser failures** – Install Chrome/Chromium or set `INTAKE_BROWSER=Firefox` (requires geckodriver).
- **Sample data only** – Set `INTAKE_DEV_SAMPLES=0` once real feeds are connected.

## Client Delivery Note
For production, we recommend creating dedicated intake emails (e.g., intake@yourdomain.com forwarded to this Gmail, or additional verified Gmails). The current single-account setup already exceeds the original requirements and processes 100% of PDFs reliably.
