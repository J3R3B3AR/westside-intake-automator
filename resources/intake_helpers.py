"""Utility helpers for the Westside intake robot."""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List

import pdfplumber
from fpdf import FPDF


@dataclass
class PatientRecord:
    """Container for parsed patient fields."""

    first_name: str = ""
    last_name: str = ""
    dob: str = ""
    phone: str = ""
    email: str = ""
    insurance: str = ""
    member_id: str = ""
    referring_physician: str = ""
    confidence: float = 0.0


class IntakeHelpers:
    """Robot Framework library exposing helper keywords."""

    ROBOT_LIBRARY_SCOPE = "GLOBAL"

    def __init__(self) -> None:
        self._field_patterns = {
            "first_name": r"First Name:\s*(.+)",
            "last_name": r"Last Name:\s*(.+)",
            "dob": r"DOB:\s*(.+)",
            "phone": r"Phone:\s*(.+)",
            "email": r"Email:\s*(.+)",
            "insurance": r"Insurance:\s*(.+)",
            "member_id": r"Member ID:\s*(.+)",
            "referring_physician": r"Referring Physician:\s*(.+)",
        }

    # Keyword: Extract Patient Fields
    def extract_patient_fields(self, pdf_path: str) -> Dict[str, str]:
        """Parse the provided PDF and return a normalized patient dictionary.

        Parameters
        ----------
        pdf_path: str
            Absolute or relative path to the intake PDF we need to read.

        Returns
        -------
        Dict[str, str]
            Dictionary containing all required patient fields plus a
            confidence score so Robot Framework can decide whether to
            continue or raise an exception.
        """

        text = self._read_pdf_text(pdf_path)
        record = PatientRecord()
        for field, pattern in self._field_patterns.items():
            value = self._search_value(pattern, text)
            setattr(record, field, value)

        record.dob = self._normalize_date(record.dob)
        record.phone = self._normalize_phone(record.phone)
        record.email = record.email.strip()
        record.confidence = self._calculate_confidence(record)

        payload = record.__dict__.copy()
        payload.setdefault("insurance", "")
        payload.setdefault("referring_physician", "")
        return payload

    # Keyword: Format Patient Filename
    def format_patient_filename(self, patient: Dict[str, str]) -> str:
        """Create a sanitized archive filename for the given patient record.

        Ensures the downstream Robot keywords always move PDFs using
        Windows-safe characters and a predictable Last_First_DOB format.
        """

        last = self._slugify(patient.get("last_name", "Unknown")) or "Unknown"
        first = self._slugify(patient.get("first_name", "Patient")) or "Patient"
        dob = self._sanitize_dob_for_filename(patient.get("dob", "01011970"))
        return f"{last}_{first}_{dob}.pdf"

    # Keyword: Ensure Sample Pdf
    def ensure_sample_pdf(self, target_dir: str) -> str:
        """Create a synthetic intake PDF for local dry-runs if one is missing."""

        directory = Path(target_dir)
        directory.mkdir(parents=True, exist_ok=True)
        sample = directory / "intake_sample.pdf"
        if sample.exists():
            return str(sample)

        pdf = FPDF()
        pdf.add_page()
        pdf.set_font("Arial", size=12)
        for line in self._sample_lines():
            pdf.cell(0, 10, txt=line, ln=1)
        pdf.output(sample)
        return str(sample)

    # Internal helpers
    def _sample_lines(self) -> List[str]:
        """Return the canned content used when generating sample PDFs."""

        return [
            "First Name: Jane",
            "Last Name: Doe",
            "DOB: 02/14/1990",
            "Phone: (555) 123-4567",
            "Email: jane.doe@example.com",
            "Insurance: Best Health Co",
            "Member ID: A123456789",
            "Referring Physician: Dr. Smith",
        ]

    def _read_pdf_text(self, pdf_path: str) -> str:
        """Extract raw text from every page in the supplied PDF."""

        pdf_file = Path(pdf_path)
        if not pdf_file.exists():
            raise FileNotFoundError(f"PDF not found at {pdf_path}")
        chunks: List[str] = []
        with pdfplumber.open(pdf_file) as pdf:
            for page in pdf.pages:
                chunks.append(page.extract_text() or "")
        return "\n".join(chunks)

    def _search_value(self, pattern: str, text: str) -> str:
        """Run case-insensitive regex search and return the stripped match."""

        match = re.search(pattern, text, re.IGNORECASE)
        if not match:
            return ""
        return match.group(1).strip()

    def _normalize_date(self, value: str) -> str:
        """Convert multiple DOB formats into MM/DD/YYYY."""

        cleaned = value.strip()
        for fmt in ("%m/%d/%Y", "%m-%d-%Y", "%Y-%m-%d", "%m/%d/%y"):
            try:
                return datetime.strptime(cleaned, fmt).strftime("%m/%d/%Y")
            except ValueError:
                continue
        return "01/01/1970"

    def _normalize_phone(self, value: str) -> str:
        """Strip non-digits and return a standardized phone format."""

        digits = re.sub(r"\D", "", value)
        if len(digits) == 10:
            return f"{digits[0:3]}-{digits[3:6]}-{digits[6:]}"
        return digits or "000-000-0000"

    def _calculate_confidence(self, record: PatientRecord) -> float:
        """Return a simple completion ratio for the captured patient fields."""

        fields = [
            record.first_name,
            record.last_name,
            record.dob,
            record.phone,
            record.email,
            record.insurance,
            record.member_id,
            record.referring_physician,
        ]
        filled = len([field for field in fields if field])
        return round(filled / len(fields), 2)

    def _slugify(self, value: str) -> str:
        """Convert arbitrary text into an uppercase slug safe for filenames."""

        cleaned = re.sub(r"[^A-Za-z0-9]+", "_", value.strip())
        return cleaned.strip("_").upper()

    def _sanitize_dob_for_filename(self, dob: str) -> str:
        """Convert DOB to digits-only string for archive file naming."""

        digits = re.sub(r"\D", "", dob)
        return digits or "01011970"