// Create a complete Robocorp RPA project for automating patient intake PDF processing. This is a Python-based robot using Robocorp libraries. The goal is to monitor a single Gmail inbox and one Google Drive folder for new PDF attachments/files, extract specific fields, create a mock Athenahealth patient chart via browser automation, archive the PDF with a renamed format, and handle exceptions by moving to an Exceptions folder and sending an email alert.
// Project Structure:
// - robot.yaml: Define dependencies and environment.
// - tasks.robot: Main Robot Framework file with keywords and tasks.
// - README.md: Detailed documentation including setup, running, testing, deployment, and GitHub push instructions.
// - mock_athena.html: A simple local HTML file to simulate Athenahealth login and form.
// - requirements.txt: If needed for any pure Python deps (but stick to RPA libs).
// - Additional files: Any helper Python modules if complex.
// Libraries to Use (import in robot.yaml and tasks):
// RPA.Email.ImapSmtp (for monitoring inboxes and sending alerts)
// RPA.Google (for Drive access: polling folder, moving/renaming files)
// RPA.PDF (for extracting text/fields from PDFs, handle OCR if needed)
// RPA.Browser.Selenium (for mock Athenahealth: open local HTML, fill form, "submit")
// RPA.FileSystem (for local file handling)
// RPA.Dialogs or RPA.Notifier (optional for alerts)
// Mock Credentials (hardcode for testing, advise to env var in docs):
// Email: jeremy.e.vargo.schedule@gmail.com (app pw: xxxx xxxx xxxx xxxx)
// Drive: Folder ID '1aBcDeFgHiJkLmNoPqRsTuVwXyZ' (advise user to replace)
// Athena Mock: Local http://localhost:8000/mock_athena.html (username: testuser@westside.com, pw: MockEHR123!)
// Extract These Fields from PDF:
// - First Name
// - Last Name
// - DOB (convert to MM/DD/YYYY)
// - Phone
// - Email
// - Insurance Name
// - Member ID
// - Referring Physician (if present)
// Main Task Flow in tasks.robot:
// 1. Check emails (IMAP) for new messages with PDF attachments, download them.
// 2. Poll Google Drive for new PDFs in "Patient Intake Uploads" folder.
// 3. For each PDF: Parse with RPA.PDF/pdfplumber, extract fields (use regex/mapping for accuracy).
// 4. Start local server if needed (subprocess for http.server on port 8000).
// 5. Open browser, "log in" to mock Athena, fill form with extracted data, upload PDF as attachment, submit (log success).
// 6. Rename PDF to LastName_FirstName_DOBMMDDYYYY.pdf and move to "Archived" subfolder in Drive.
// 7. If extraction/login fails (e.g., low confidence <95%), move to "Exceptions" subfolder and send SMTP email to alex@westsidebilling.com with reason.
// Error Handling: Log everything, retry on transient errors, alert on failures.
// Scheduling: In docs, include steps to upload to Robocorp Cloud and schedule every 15 min.
// Commands to Generate in README.md:
// - Setup: pip install -r requirements.txt (if any), robocorp lab setup.
// - Local Test: rcc run
// - Deploy: rcc cloud push
// - Schedule: Instructions for Robocorp Control Room cron */15 * * * *
// - GitHub Push: git init, git add ., git commit -m "Initial RPA project", git remote add origin [repo], git push -u origin main
// Make code clean, commented, modular. Generate as much as possible in one go: robot.yaml, tasks.robot, README.md, mock_athena.html.
// Finally, in README, add section: "When complete, push to GitHub: Create repo on GitHub, then run the git commands above."

*** Settings ***
Documentation     Westside Intake Automator fulfills the intake pipeline outlined above.
...               It monitors Gmail and Drive, parses PDFs, drives the mock Athena UI, and
...               archives or escalates every document with structured logging.
Library           Collections
Library           DateTime
Library           OperatingSystem
Library           Process
Library           RPA.Browser.Selenium    auto_close=${FALSE}
Library           RPA.Email.ImapSmtp
Library           RPA.FileSystem
Library           RPA.Cloud.Google    WITH NAME    Google
Library           RPA.Notifier
Library           RPA.PDF
Library           String
Library           resources.intake_helpers.IntakeHelpers    WITH NAME    IntakeUtils
Suite Setup       Setup Intake Suite
Suite Teardown    Teardown Intake Suite
Test Tags         intake    westside

*** Variables ***
${OUTPUT_ROOT}                    ${CURDIR}${/}output
${DOWNLOAD_ROOT}                  ${OUTPUT_ROOT}${/}downloads
${ARCHIVE_ROOT}                   ${OUTPUT_ROOT}${/}archived
${EXCEPTION_ROOT}                 ${OUTPUT_ROOT}${/}exceptions
${SAMPLE_ROOT}                    ${CURDIR}${/}samples
${LOCAL_SERVER_PORT}              8000
${ATHENA_BASE_URL}                http://localhost:8000/mock_athena.html
${ATHENA_USERNAME}                testuser@westside.com
${ATHENA_PASSWORD}                MockEHR123!
${BROWSER}                        Chrome
${PDF_CONFIDENCE_THRESHOLD}       0.95
${PRIMARY_EMAIL_ADDRESS}          jeremy.e.vargo.schedule@gmail.com
${PRIMARY_APP_PASSWORD}           xxxx xxxx xxxx xxxx
${SMTP_SENDER}                    ${PRIMARY_EMAIL_ADDRESS}
${SMTP_APP_PASSWORD}              ${PRIMARY_APP_PASSWORD}
${ALERT_RECIPIENT}                alex@westsidebilling.com
${GOOGLE_SERVICE_ACCOUNT}         ${CURDIR}${/}service_account.json
${DRIVE_ROOT_FOLDER}              Patient Intake Uploads
${DRIVE_ARCHIVE_PATH}             ${DRIVE_ROOT_FOLDER}${/}Archived
${DRIVE_EXCEPTION_PATH}           ${DRIVE_ROOT_FOLDER}${/}Exceptions
${DEV_SAMPLE_ENABLED}             1
${ATHENA_SERVER_HANDLE}           ${NONE}
${ATHENA_SERVER_READY}            ${FALSE}
${ATHENA_BROWSER_ACTIVE}          ${FALSE}
${GOOGLE_READY}                   ${FALSE}
${PROCESSED_COUNT}                0
${FAILED_COUNT}                   0
@{PENDING_DOCUMENTS}              @{EMPTY}

*** Tasks ***
Process Patient Intake Packages
	Initialize Intake Run
	Collect Intake Sources
	Process Intake Queue
	Summarize Intake Run

*** Keywords ***
Setup Intake Suite
	Log    Bootstrapping Westside Intake Automator.    INFO
	Load Environment Overrides
	Build Email Account List
	OperatingSystem.Create Directory    ${OUTPUT_ROOT}
	OperatingSystem.Create Directory    ${DOWNLOAD_ROOT}
	OperatingSystem.Create Directory    ${ARCHIVE_ROOT}
	OperatingSystem.Create Directory    ${EXCEPTION_ROOT}
	Set Suite Variable    @{PENDING_DOCUMENTS}    @{EMPTY}
	Set Suite Variable    ${PROCESSED_COUNT}    0
	Set Suite Variable    ${FAILED_COUNT}    0

Teardown Intake Suite
	Run Keyword And Ignore Error    Close All Browsers
	Stop Mock Athena Server
	Log    Westside Intake Automator finished. Processed=${PROCESSED_COUNT}, Failed=${FAILED_COUNT}.    INFO

Load Environment Overrides
	${port}=    Get Environment Variable    MOCK_SERVER_PORT    ${LOCAL_SERVER_PORT}
	Set Suite Variable    ${LOCAL_SERVER_PORT}    ${port}
	${base_url}=    Get Environment Variable    ATHENA_BASE_URL    ${ATHENA_BASE_URL}
	Set Suite Variable    ${ATHENA_BASE_URL}    ${base_url}
	${athena_user}=    Get Environment Variable    ATHENA_USERNAME    ${ATHENA_USERNAME}
	Set Suite Variable    ${ATHENA_USERNAME}    ${athena_user}
	${athena_pass}=    Get Environment Variable    ATHENA_PASSWORD    ${ATHENA_PASSWORD}
	Set Suite Variable    ${ATHENA_PASSWORD}    ${athena_pass}
	${browser}=    Get Environment Variable    INTAKE_BROWSER    ${BROWSER}
	Set Suite Variable    ${BROWSER}    ${browser}
	${threshold_raw}=    Get Environment Variable    PDF_CONFIDENCE_THRESHOLD    ${PDF_CONFIDENCE_THRESHOLD}
	${threshold}=    Convert To Number    ${threshold_raw}
	Set Suite Variable    ${PDF_CONFIDENCE_THRESHOLD}    ${threshold}
	${primary_email}=    Get Environment Variable    PRIMARY_INBOX    ${PRIMARY_EMAIL_ADDRESS}
	Set Suite Variable    ${PRIMARY_EMAIL_ADDRESS}    ${primary_email}
	${primary_pw}=    Get Environment Variable    PRIMARY_APP_PASSWORD    ${PRIMARY_APP_PASSWORD}
	Set Suite Variable    ${PRIMARY_APP_PASSWORD}    ${primary_pw}
	${smtp_sender}=    Get Environment Variable    SMTP_SENDER    ${SMTP_SENDER}
	Set Suite Variable    ${SMTP_SENDER}    ${smtp_sender}
	${smtp_pw}=    Get Environment Variable    SMTP_APP_PASSWORD    ${SMTP_APP_PASSWORD}
	Set Suite Variable    ${SMTP_APP_PASSWORD}    ${smtp_pw}
	${alert}=    Get Environment Variable    ALERT_RECIPIENT    ${ALERT_RECIPIENT}
	Set Suite Variable    ${ALERT_RECIPIENT}    ${alert}
	${service_account}=    Get Environment Variable    GOOGLE_APPLICATION_CREDENTIALS    ${GOOGLE_SERVICE_ACCOUNT}
	Set Suite Variable    ${GOOGLE_SERVICE_ACCOUNT}    ${service_account}
	${root_folder}=    Get Environment Variable    DRIVE_ROOT_FOLDER    ${DRIVE_ROOT_FOLDER}
	Set Suite Variable    ${DRIVE_ROOT_FOLDER}    ${root_folder}
	Set Suite Variable    ${DRIVE_ARCHIVE_PATH}    ${DRIVE_ROOT_FOLDER}${/}Archived
	Set Suite Variable    ${DRIVE_EXCEPTION_PATH}    ${DRIVE_ROOT_FOLDER}${/}Exceptions
	${samples_flag}=    Get Environment Variable    INTAKE_DEV_SAMPLES    ${DEV_SAMPLE_ENABLED}
	Set Suite Variable    ${DEV_SAMPLE_ENABLED}    ${samples_flag}

Build Email Account List
	${intake}=    Create Dictionary    label=Intake Inbox    address=${PRIMARY_EMAIL_ADDRESS}    password=${PRIMARY_APP_PASSWORD}
	@{accounts}=    Create List    ${intake}
	Set Suite Variable    @{EMAIL_ACCOUNTS}    @{accounts}
	${account_list}=    Create List    @{accounts}
	Set Suite Variable    ${EMAIL_ACCOUNTS}    ${account_list}

Initialize Intake Run
	Start Mock Athena Server
	Ensure Google Drive Client
	Log    Intake run initialized with dedicated Gmail inbox ${PRIMARY_EMAIL_ADDRESS} and Drive root ${DRIVE_ROOT_FOLDER}.    INFO

Collect Intake Sources
	${records}=    Create List
	${email_records}=    Collect Gmail Attachments
	FOR    ${item}    IN    @{email_records}
		Append To List    ${records}    ${item}
	END
	${drive_records}=    Collect Drive Uploads
	FOR    ${item}    IN    @{drive_records}
		Append To List    ${records}    ${item}
	END
	${sample_records}=    Collect Sample PDFs When Enabled
	FOR    ${item}    IN    @{sample_records}
		Append To List    ${records}    ${item}
	END
	${unique}=    Remove Duplicate Records    ${records}
	Set Suite Variable    @{PENDING_DOCUMENTS}    @{unique}
	${count}=    Get Length    ${unique}
	Log    Prepared ${count} intake PDF(s) for processing.    INFO

Process Intake Queue
	${pending}=    Get Length    ${PENDING_DOCUMENTS}
	Run Keyword If    ${pending} == 0    Log    No intake PDFs waiting.    WARN    ELSE    Run Keyword    Iterate Intake Queue

Iterate Intake Queue
	FOR    ${record}    IN    @{PENDING_DOCUMENTS}
		TRY
			${patient}=    Parse Intake Pdf    ${record}
			Validate Extraction Confidence    ${patient}
			Submit Patient Intake Via Athena    ${patient}    ${record}
			Archive Successful Intake    ${record}    ${patient}
			Increment Success Counter
		EXCEPT    AS    ${err}
			Handle Intake Failure    ${record}    ${err}
		END
	END

Summarize Intake Run
	Log    Intake summary => Success: ${PROCESSED_COUNT}, Failed: ${FAILED_COUNT}.    INFO
	Run Keyword If    ${FAILED_COUNT} > 0    Log    Exceptions detected, review ${EXCEPTION_ROOT}.    WARN

Collect Gmail Attachments
	${aggregated}=    Create List
	FOR    ${account}    IN    @{EMAIL_ACCOUNTS}
		${status}    ${files}=    Run Keyword And Ignore Error    Download Gmail Attachments    ${account}
		Run Keyword If    '${status}' == 'PASS'    FOR    ${item}    IN    @{files}
		...    Append To List    ${aggregated}    ${item}
		...    END
		Run Keyword If    '${status}' != 'PASS'    Log    Email collection skipped for ${account}[label]: ${files}.    WARN
	END
	Return From Keyword    ${aggregated}

Download Gmail Attachments
	[Arguments]    ${account}
	${address}=    Set Variable    ${account}[address]
	${password}=   Set Variable    ${account}[password]
	Authorize Imap    ${address}    ${password}    imap.gmail.com    993
	Select Folder    INBOX
	${messages}=    List Messages    criterion=UNSEEN
	${downloads}=    Create List
	FOR    ${msg}    IN    @{messages}
		${attachments}=    Save Attachment    ${msg}    target_folder=${DOWNLOAD_ROOT}    overwrite=${TRUE}    pattern=*.pdf
		FOR    ${path}    IN    @{attachments}
			${record}=    Create Dictionary    path=${path}    source=${account}[label]    origin=email
			Append To List    ${downloads}    ${record}
		END
	END
	Return From Keyword    ${downloads}

Collect Drive Uploads
	${drive_records}=    Create List
	Run Keyword If    not ${GOOGLE_READY}    Return From Keyword    ${drive_records}
	${query}=    Set Variable    name contains '.pdf'
	${files}=    Google.Search Drive Files    query=${query}    source=${DRIVE_ROOT_FOLDER}
	FOR    ${file}    IN    @{files}
		${tempdir}=    Set Variable    ${DOWNLOAD_ROOT}
		${downloaded}=    Google.Download Drive Files    file_dict=${file}
		FOR    ${entry}    IN    @{downloaded}
			${source_path}=    Catenate    SEPARATOR=${/}    ${CURDIR}    ${entry}[name]
			${target_path}=    Catenate    SEPARATOR=${/}    ${tempdir}    ${entry}[name]
			Run Keyword If    '${source_path}' != '${target_path}'    RPA.FileSystem.Move File    ${source_path}    ${target_path}
			${record}=    Create Dictionary    path=${target_path}    source=Drive Uploads    origin=drive    drive_id=${entry}[id]
			Append To List    ${drive_records}    ${record}
		END
	END
	Return From Keyword    ${drive_records}

Collect Sample PDFs When Enabled
	${records}=    Create List
	${enabled}=    Evaluate    str(${DEV_SAMPLE_ENABLED}).lower() not in ('0','false','off')
	Run Keyword If    not ${enabled}    Return From Keyword    ${records}
	${sample_path}=    IntakeUtils.Ensure Sample Pdf    ${SAMPLE_ROOT}
	${record}=    Create Dictionary    path=${sample_path}    source=Dev Sample    origin=sample
	Append To List    ${records}    ${record}
	Return From Keyword    ${records}

Remove Duplicate Records
	[Arguments]    ${records}
	${seen}=    Create List
	${unique}=    Create List
	FOR    ${entry}    IN    @{records}
		${signature}=    Catenate    SEPARATOR=::    ${entry}[source]    ${entry}[path]
		${already}=    Run Keyword And Return Status    List Should Contain Value    ${seen}    ${signature}
		Run Keyword If    ${already}    Continue For Loop
		Append To List    ${seen}    ${signature}
		Append To List    ${unique}    ${entry}
	END
	Return From Keyword    ${unique}

Parse Intake Pdf
	[Arguments]    ${record}
	${patient}=    IntakeUtils.Extract Patient Fields    ${record}[path]
	Log    Parsed ${patient}[first_name] ${patient}[last_name] from ${record}[source].    INFO
	Set To Dictionary    ${patient}    file_path=${record}[path]
	Return From Keyword    ${patient}

Validate Extraction Confidence
	[Arguments]    ${patient}
	${confidence}=    Set Variable    ${patient}[confidence]
	Run Keyword If    ${confidence} < ${PDF_CONFIDENCE_THRESHOLD}    Fail    Extraction confidence ${confidence} below threshold ${PDF_CONFIDENCE_THRESHOLD}.

Submit Patient Intake Via Athena
	[Arguments]    ${patient}    ${record}
	Open Athena Session
	Input Text    css=#patient-first-name    ${patient}[first_name]
	Input Text    css=#patient-last-name    ${patient}[last_name]
	Input Text    css=#patient-dob    ${patient}[dob]
	Input Text    css=#patient-phone    ${patient}[phone]
	Input Text    css=#patient-email    ${patient}[email]
	Input Text    css=#patient-insurance    ${patient}[insurance]
	Input Text    css=#patient-member-id    ${patient}[member_id]
	Input Text    css=#patient-referrer    ${patient}[referring_physician]
	Choose File    css=#patient-document    ${record}[path]
	Click Button    css=#submit-intake
	Wait Until Page Contains Element    css=#submit-toast    timeout=10s

Archive Successful Intake
	[Arguments]    ${record}    ${patient}
	${filename}=    IntakeUtils.Format Patient Filename    ${patient}
	${target}=    Catenate    SEPARATOR=${/}    ${ARCHIVE_ROOT}    ${filename}
	RPA.FileSystem.Move File    ${record}[path]    ${target}
	${drive_status}=    Run Keyword And Return Status    Upload Drive Archive    ${target}
	Run Keyword If    not ${drive_status}    Log    Drive archive skipped for ${filename}.    WARN

Upload Drive Archive
	[Arguments]    ${local_path}
	Run Keyword If    not ${GOOGLE_READY}    Return From Keyword
	${status}=    Run Keyword And Return Status    Google.Upload Drive File    ${local_path}    ${DRIVE_ARCHIVE_PATH}    overwrite=${TRUE}    make_dir=${TRUE}
	Run Keyword If    not ${status}    Fail    Drive upload failed for ${local_path}

Increment Success Counter
	${count}=    Evaluate    ${PROCESSED_COUNT} + 1
	Set Suite Variable    ${PROCESSED_COUNT}    ${count}

Handle Intake Failure
	[Arguments]    ${record}    ${error}
	Log    Intake failure for ${record}[path]: ${error}.    ERROR
	${timestamp}=    DateTime.Get Current Date    result_format=%Y%m%d_%H%M%S
	${basename}=    Get File Name    ${record}[path]
	${target}=    Catenate    SEPARATOR=${/}    ${EXCEPTION_ROOT}    ${timestamp}_${basename}
	RPA.FileSystem.Move File    ${record}[path]    ${target}
	Run Keyword If    ${GOOGLE_READY}    Run Keyword And Ignore Error    Google.Upload Drive File    ${target}    ${DRIVE_EXCEPTION_PATH}    make_dir=${TRUE}    overwrite=${TRUE}
	Send Exception Alert    ${target}    ${error}
	${count}=    Evaluate    ${FAILED_COUNT} + 1
	Set Suite Variable    ${FAILED_COUNT}    ${count}

Send Exception Alert
	[Arguments]    ${path}    ${error}
	${body}=    Catenate    SEPARATOR=\n    Patient intake failed for ${path}.    Reason: ${error}
	${authorized}=    Run Keyword And Return Status    Authorize Smtp    smtp.gmail.com    587    ${SMTP_SENDER}    ${SMTP_APP_PASSWORD}    ${TRUE}
	Run Keyword If    not ${authorized}    Log    SMTP authorization failed; alert not sent.    WARN
	Run Keyword If    not ${authorized}    Return From Keyword
	${status}=    Run Keyword And Return Status    Send Message    ${SMTP_SENDER}    ${ALERT_RECIPIENT}    subject=Intake Failure Alert    body=${body}
	Run Keyword If    not ${status}    Log    Could not send exception email to ${ALERT_RECIPIENT}.    WARN

Ensure Google Drive Client
	${exists}=    Run Keyword And Return Status    File Should Exist    ${GOOGLE_SERVICE_ACCOUNT}
	Run Keyword If    not ${exists}    Log    Google credentials missing at ${GOOGLE_SERVICE_ACCOUNT}. Drive operations disabled.    WARN
	Run Keyword If    not ${exists}    Return From Keyword
	${status}=    Run Keyword And Return Status    Google.Init Drive    service_account=${GOOGLE_SERVICE_ACCOUNT}
	Run Keyword If    ${status}    Set Suite Variable    ${GOOGLE_READY}    ${TRUE}
	Run Keyword If    not ${status}    Log    Drive client initialization failed.    WARN

Start Mock Athena Server
	Run Keyword If    ${ATHENA_SERVER_READY}    Return From Keyword
	${python}=    Evaluate    __import__('sys').executable
	${log}=    Catenate    SEPARATOR=${/}    ${OUTPUT_ROOT}    mock_athena.log
	${handle}=    Start Process    ${python}    -m    http.server    ${LOCAL_SERVER_PORT}    cwd=${CURDIR}    stdout=${log}    stderr=STDOUT
	Sleep    1s
	Set Suite Variable    ${ATHENA_SERVER_HANDLE}    ${handle}
	Set Suite Variable    ${ATHENA_SERVER_READY}    ${TRUE}

Stop Mock Athena Server
	Run Keyword If    not ${ATHENA_SERVER_READY}    Return From Keyword
	Terminate Process    ${ATHENA_SERVER_HANDLE}    kill=${TRUE}
	Set Suite Variable    ${ATHENA_SERVER_READY}    ${FALSE}
	Set Suite Variable    ${ATHENA_SERVER_HANDLE}    ${NONE}

Open Athena Session
	Run Keyword If    not ${ATHENA_BROWSER_ACTIVE}    Launch Athena Browser Session

Launch Athena Browser Session
	@{arguments}=    Create List    --headless=new    --disable-gpu    --window-size=1400,900
	${options}=    Create Dictionary
	Set To Dictionary    ${options}    arguments=${arguments}
	Open Available Browser    ${ATHENA_BASE_URL}    browser=${BROWSER}    options=${options}
	Wait Until Page Contains Element    css=#login-email    timeout=10s
	Input Text    css=#login-email    ${ATHENA_USERNAME}
	Input Text    css=#login-password    ${ATHENA_PASSWORD}
	Click Button    css=#login-submit
	Wait Until Page Contains Element    css=#intake-form    timeout=10s
	Set Suite Variable    ${ATHENA_BROWSER_ACTIVE}    ${TRUE}

Ensure Message Client
	[Arguments]    ${address}    ${password}
	${status}=    Run Keyword And Return Status    Authorize Smtp    smtp.gmail.com    587    ${address}    ${password}    ${TRUE}
	Run Keyword If    not ${status}    Log    SMTP authorization failed for ${address}.    WARN
	Return From Keyword    ${status}
