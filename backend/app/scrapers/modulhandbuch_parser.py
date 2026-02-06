"""
Modulhandbuch PDF Parser - Extracts module requirements from curriculum PDFs.

Uses pdfplumber for layout-based text extraction, suitable for
TU Dortmund Informatik faculty Modulhandbuch PDFs.

OPTIMIZED: Only parses first 5 pages (table of contents) for efficiency.
"""

import logging
import re
import tempfile
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict

try:
    import pdfplumber
    PDFPLUMBER_AVAILABLE = True
except ImportError:
    PDFPLUMBER_AVAILABLE = False
    pdfplumber = None

import requests

logger = logging.getLogger(__name__)


@dataclass
class Module:
    """Represents a curriculum module."""
    module_id: str
    name: str
    ects: int
    category: str  # "Pflicht" (mandatory), "Wahlpflicht" (elective), "Fachprojekt", "Wahlmodul"
    semester: Optional[str] = None
    area: Optional[str] = None


@dataclass
class CurriculumRequirements:
    """Complete curriculum requirements parsed from Modulhandbuch."""
    mandatory_modules: List[Module]
    elective_areas: Dict[str, int]  # area_name -> required ECTS
    total_ects: int
    source_pdf: str


class ModulhandbuchParser:
    """
    Parses Modulhandbuch PDFs to extract module requirements.
    
    OPTIMIZED: Extracts from table of contents (first 5 pages) only.
    """
    
    # Standard ECTS values based on module type for TU Dortmund Informatik
    DEFAULT_ECTS = {
        'Pflicht': 8,      # Pflichtmodule typically 8 ECTS
        'Wahlpflicht': 4,  # Wahlpflichtmodule typically 4-8 ECTS
        'Fachprojekt': 8,  # Fachprojekte typically 8 ECTS
        'Wahlmodul': 4,    # Wahlmodule typically 4 ECTS
    }
    
    def __init__(self, pdf_url: str):
        """Initialize parser with PDF URL."""
        self.pdf_url = pdf_url
        self.pdf_path: Optional[str] = None
        self._pages_cache: Optional[List[str]] = None
        
    def download_pdf(self) -> bool:
        """Download PDF to temporary file."""
        try:
            logger.info(f"Downloading PDF: {self.pdf_url}")
            response = requests.get(self.pdf_url, timeout=30)
            response.raise_for_status()
            
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf') as f:
                f.write(response.content)
                self.pdf_path = f.name
            
            logger.info(f"PDF downloaded to: {self.pdf_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to download PDF: {e}")
            return False
    
    def extract_first_pages(self, max_pages: int = 5) -> List[str]:
        """Extract text from first N pages only (table of contents)."""
        if self._pages_cache:
            return self._pages_cache
            
        if not PDFPLUMBER_AVAILABLE:
            logger.error("pdfplumber not available - cannot parse PDF")
            return []
        
        if not self.pdf_path and not self.download_pdf():
            return []
        
        try:
            pages_text = []
            with pdfplumber.open(self.pdf_path) as pdf:
                logger.info(f"PDF has {len(pdf.pages)} pages, extracting first {max_pages}")
                for page in pdf.pages[:max_pages]:
                    text = page.extract_text() or ""
                    pages_text.append(text)
            
            self._pages_cache = pages_text
            return pages_text
            
        except Exception as e:
            logger.error(f"Failed to extract PDF text: {e}")
            return []
    
    def extract_modules(self) -> List[Module]:
        """
        Extract module information from PDF table of contents.
        
        Pattern: INF-BSc-XXX:ModuleName(Abbreviation)
        """
        pages = self.extract_first_pages()
        if not pages:
            return []
        
        # Combine first pages into single text
        full_text = "\n".join(pages)
        
        modules = []
        
        # Pattern to match module entries like:
        # INF-BSc-101:Rechnerstrukturen(RS) . . . 5
        # The module name is the first non-whitespace word(s) after the colon
        # Using \S+ to capture contiguous module name before dots/spaces
        module_pattern = re.compile(
            r'(INF-(?:BSc|Math|ETIT)-\d+):(\S+)',
            re.MULTILINE
        )
        
        # Build category ranges by finding section headers
        category_ranges = []  # (start_pos, category)
        
        # Find section markers in the text (case insensitive)
        text_lower = full_text.lower()
        
        # Look for key section headers
        markers = [
            ('wahlpflichtmodule', 'Wahlpflicht'),
            ('katalog', 'Wahlpflicht'),  # "Katalog Konzepte für Software" etc
            ('fachprojekte', 'Fachprojekt'),
            ('wahlmodule ', 'Wahlmodul'),  # Space to avoid matching 'wahlpflichtmodule'
        ]
        
        for marker, category in markers:
            pos = text_lower.find(marker)
            if pos > 0:
                category_ranges.append((pos, category))
                logger.debug(f"Found '{marker}' at position {pos} -> {category}")
        
        # Sort by position
        category_ranges.sort(key=lambda x: x[0])
        
        # Find all module matches
        for match in module_pattern.finditer(full_text):
            module_id = match.group(1).strip()
            raw_name = match.group(2).strip()
            
            # Clean up the name
            # Remove trailing dots, page numbers, and whitespace
            name = re.sub(r'[\.\s]+$', '', raw_name)  # Remove trailing dots/spaces
            name = re.sub(r'\s+', ' ', name)  # Normalize whitespace
            
            # Skip if name is too short
            if len(name) < 3:
                continue
            
            # Determine category based on position in text
            match_pos = match.start()
            current_cat = 'Pflicht'  # Default
            for pos, cat in category_ranges:
                if pos <= match_pos:
                    current_cat = cat
            
            # Get default ECTS for this category
            ects = self.DEFAULT_ECTS.get(current_cat, 4)
            
            module = Module(
                module_id=module_id,
                name=name,
                ects=ects,
                category=current_cat,
                area=current_cat
            )
            modules.append(module)
        
        logger.info(f"Extracted {len(modules)} modules from PDF table of contents")
        return modules
    
    def extract_requirements(self) -> Optional[CurriculumRequirements]:
        """Extract complete curriculum requirements."""
        modules = self.extract_modules()
        
        if not modules:
            logger.warning("No modules extracted from PDF")
            return None
        
        # Separate by category
        mandatory = [m for m in modules if m.category == "Pflicht"]
        wahlpflicht = [m for m in modules if m.category == "Wahlpflicht"]
        fachprojekte = [m for m in modules if m.category == "Fachprojekt"]
        wahlmodule = [m for m in modules if m.category == "Wahlmodul"]
        
        # Group electives by area and calculate required ECTS
        elective_areas: Dict[str, int] = {}
        for m in wahlpflicht + fachprojekte + wahlmodule:
            area = m.area or "Allgemeiner Wahlpflichtbereich"
            if area not in elective_areas:
                elective_areas[area] = 0
            elective_areas[area] += m.ects
        
        # Calculate total (Bachelor typically 180 ECTS)
        total_ects = sum(m.ects for m in mandatory) + sum(elective_areas.values())
        
        return CurriculumRequirements(
            mandatory_modules=mandatory,
            elective_areas=elective_areas,
            total_ects=total_ects if total_ects > 0 else 180,
            source_pdf=self.pdf_url
        )
    
    def to_dict(self) -> Dict:
        """Convert requirements to JSON-serializable dict."""
        req = self.extract_requirements()
        if not req:
            # Return empty structure instead of error
            return {
                "mandatory_modules": [],
                "elective_areas": {},
                "total_ects": 180,
                "source_pdf": self.pdf_url
            }
        
        return {
            "mandatory_modules": [asdict(m) for m in req.mandatory_modules],
            "elective_areas": req.elective_areas,
            "total_ects": req.total_ects,
            "source_pdf": req.source_pdf
        }


def parse_modulhandbuch(pdf_url: str) -> Dict:
    """
    Main entry point: Parse a Modulhandbuch PDF.
    
    Args:
        pdf_url: URL to the PDF
        
    Returns:
        Dict with parsed requirements or error
    """
    if not PDFPLUMBER_AVAILABLE:
        return {"error": "pdfplumber not installed", "modules": []}
    
    parser = ModulhandbuchParser(pdf_url)
    return parser.to_dict()
