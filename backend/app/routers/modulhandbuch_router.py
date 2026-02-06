"""
Modulhandbuch Router - Routes to correct curriculum PDF based on degree identity.

This module maps degree subjects to their corresponding Modulhandbuch URLs
at TU Dortmund faculty websites.
"""

import logging
import re
import requests
from bs4 import BeautifulSoup
from typing import Dict, Optional, List

logger = logging.getLogger(__name__)

# Knowledge Map: Degree subject to Modulhandbuch URL routing
MODULHANDBUCH_ROUTES = {
    # Informatik Faculty (cs.tu-dortmund.de)
    "Informatik": {
        "base_url": "https://cs.tu-dortmund.de/studium/poen-mhb-etc",
        "bachelor_path": "/bsc-inf/",
        "master_path": "/msc-inf/",
        "mhb_details_page": "/details/bsc-anginf-mhb-details/modulhandbuch-bsc-anginf/",
        "pdf_url": "https://cs.tu-dortmund.de/storages/cs/r/Informatik/Studiendekanat/Modulhandbuecher/BSc_Inf_AngInf/Gesamt/Inf_IMP/modulhandbuch-bachelor.pdf",
        "pdf_patterns": ["Modulhandbuch", "MHB", "modulhandbuch"],
        "parser_type": "pdfplumber"  # Layout-based
    },
    "Angewandte Informatik": {
        "base_url": "https://cs.tu-dortmund.de/studium/poen-mhb-etc",
        "bachelor_path": "/bsc-anginf/",
        "master_path": "/msc-anginf/",
        "mhb_details_page": "/details/bsc-anginf-mhb-details/modulhandbuch-bsc-anginf/",
        "pdf_url": "https://cs.tu-dortmund.de/storages/cs/r/Informatik/Studiendekanat/Modulhandbuecher/BSc_Inf_AngInf/Gesamt/Inf_IMP/modulhandbuch-bachelor.pdf",
        "pdf_patterns": ["Modulhandbuch", "MHB", "modulhandbuch"],
        "parser_type": "pdfplumber"
    },
    "Wirtschaftsinformatik": {
        "base_url": "https://cs.tu-dortmund.de/studium/poen-mhb-etc",
        "bachelor_path": "/bsc-wirtinf/",
        "master_path": "/msc-wirtinf/",
        "mhb_details_page": "/details/bsc-wirtinf-mhb-details/modulhandbuch-bsc-wirtinf/",
        "pdf_patterns": ["Modulhandbuch", "MHB", "modulhandbuch"],
        "parser_type": "pdfplumber"
    },
    
    # Physics Faculty (physik.tu-dortmund.de) - Future expansion
    # "Physik": {
    #     "base_url": "https://physik.tu-dortmund.de/studium/studiengaenge-und-qualifikation/",
    #     "parser_type": "camelot"  # Grid tables
    # },
    
    # Data Science / Statistics Faculty - Future expansion
    # "Data Science": {
    #     "base_url": "https://statistik.tu-dortmund.de/studium/studiengaenge/",
    #     "parser_type": "pdfplumber"
    # },
}

# Fallback aliases for fuzzy matching
SUBJECT_ALIASES = {
    "ang. inf.": "Angewandte Informatik",
    "angewandte info": "Angewandte Informatik",
    "wirtschaftsinfo": "Wirtschaftsinformatik",
    "winfo": "Wirtschaftsinformatik",
    "info": "Informatik",
    "cs": "Informatik",
    "computer science": "Informatik",
}


class ModulhandbuchRouter:
    """Routes degree identity to the correct Modulhandbuch PDF URL."""
    
    def __init__(self, degree_identity: Dict):
        """
        Initialize router with degree identity from BOSS.
        
        Args:
            degree_identity: Dict with keys:
                - degree_type: "Bachelor" or "Master"
                - degree_subject: e.g., "Angewandte Informatik"
                - po_version: e.g., "2023"
        """
        self.degree_type = degree_identity.get('degree_type', 'Bachelor')
        self.degree_subject = degree_identity.get('degree_subject', '')
        self.po_version = degree_identity.get('po_version', '')
        
        # Normalize subject name
        self.normalized_subject = self._normalize_subject(self.degree_subject)
        
    def _normalize_subject(self, subject: str) -> str:
        """Normalize subject name to match routing table."""
        if not subject:
            return ""
            
        subject_lower = subject.lower().strip()
        
        # Check aliases first
        for alias, canonical in SUBJECT_ALIASES.items():
            if alias in subject_lower:
                return canonical
        
        # Check exact matches in routing table
        for route_subject in MODULHANDBUCH_ROUTES.keys():
            if route_subject.lower() in subject_lower or subject_lower in route_subject.lower():
                return route_subject
        
        return subject
    
    def get_route(self) -> Optional[Dict]:
        """
        Get routing configuration for the degree.
        
        Returns:
            Dict with URL patterns or None if not found
        """
        if self.normalized_subject in MODULHANDBUCH_ROUTES:
            return MODULHANDBUCH_ROUTES[self.normalized_subject]
        
        logger.warning(f"No route found for subject: {self.degree_subject}")
        return None
    
    def get_modulhandbuch_page_url(self) -> Optional[str]:
        """
        Get the URL of the Modulhandbuch page.
        
        Returns:
            Full URL to the Modulhandbuch page
        """
        route = self.get_route()
        if not route:
            return None
        
        base_url = route['base_url']
        
        # Select path based on degree type
        if self.degree_type and 'Master' in self.degree_type:
            path = route.get('master_path', route.get('bachelor_path', ''))
        else:
            path = route.get('bachelor_path', '')
        
        return f"{base_url}{path}"
    
    def fetch_pdf_urls(self) -> List[Dict]:
        """
        Fetch list of Modulhandbuch PDF URLs from the faculty website.
        Handles intermediate pages by following links if no PDFs found initially.
        
        Returns:
            List of dicts: [{'name': 'MHB Teil 1', 'url': '...', 'po_match': True}]
        """
        page_url = self.get_modulhandbuch_page_url()
        if not page_url:
            return []
        
        try:
            logger.info(f"Fetching Modulhandbuch page: {page_url}")
            response = requests.get(page_url, timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Helper to extract PDFs from a soup object
            def extract_from_soup(current_soup, source_url):
                pdf_links = []
                route = self.get_route()
                patterns = route.get('pdf_patterns', ['Modulhandbuch'])
                
                for link in current_soup.find_all('a', href=True):
                    href = link['href']
                    text = link.get_text(strip=True)
                    
                    if '.pdf' in href.lower():
                        is_mhb = any(p.lower() in text.lower() or p.lower() in href.lower() 
                                     for p in patterns)
                        
                        if is_mhb:
                            # Check if PO version matches
                            po_match = self.po_version and self.po_version in (text + href)
                            
                            # Make URL absolute if needed
                            if not href.startswith('http'):
                                # Handle relative URLs correctly
                                if href.startswith('/'):
                                    href = f"https://cs.tu-dortmund.de{href}"
                                else:
                                    # Very simple relative handling
                                    base = source_url.rsplit('/', 1)[0]
                                    href = f"{base}/{href}"
                            
                            pdf_links.append({
                                'name': text or 'Modulhandbuch',
                                'url': href,
                                'po_match': po_match
                            })
                return pdf_links

            # Attempt 1: Look on current page
            pdf_links = extract_from_soup(soup, page_url)
            
            if not pdf_links:
                logger.info("No PDFs found on landing page. Looking for sub-page links...")
                # Attempt 2: Look for a link to the "Details" or "Modulhandbuch" page
                # The debug structure showed a tile link with "Modulhandbuch" text or inside 'details' path
                
                sub_page_url = None
                for link in soup.find_all('a', href=True):
                    href = link['href']
                    text = link.get_text(strip=True)
                    
                    # Heuristics for the sub-page link
                    if "modulhandbuch" in text.lower() or "details" in href.lower():
                        if "bsc" in href.lower() or "msc" in href.lower():
                             # Prioritize the one matching our degree type if possible
                             current_path = self.get_route().get('bachelor_path', '')
                             if current_path.strip('/') in href:
                                 pass # reinforcing match

                             sub_page_url = href
                             if not sub_page_url.startswith('http'):
                                 sub_page_url = f"https://cs.tu-dortmund.de{sub_page_url}"
                             break
                
                if sub_page_url:
                    logger.info(f"Following sub-page link: {sub_page_url}")
                    sub_response = requests.get(sub_page_url, timeout=10)
                    if sub_response.status_code == 200:
                         sub_soup = BeautifulSoup(sub_response.text, 'html.parser')
                         pdf_links = extract_from_soup(sub_soup, sub_page_url)
            
            logger.info(f"Found {len(pdf_links)} Modulhandbuch PDFs")
            return pdf_links
            
        except Exception as e:
            logger.error(f"Error fetching Modulhandbuch page: {e}")
            return []
    
    def get_best_pdf_url(self) -> Optional[str]:
        """
        Get the best matching Modulhandbuch PDF URL.
        
        Priority:
        1. Direct PDF URL from config (most reliable)
        2. PDF matching PO version from dynamic discovery
        3. First available PDF from dynamic discovery
        
        Returns:
            URL string or None
        """
        # Priority 1: Use direct PDF URL from config if available
        route = self.get_route()
        if route and route.get('pdf_url'):
            logger.info(f"Using direct PDF URL from config: {route['pdf_url']}")
            return route['pdf_url']
        
        # Priority 2 & 3: Dynamic discovery
        pdfs = self.fetch_pdf_urls()
        
        if not pdfs:
            return None
        
        # Prefer PO-matching PDF
        for pdf in pdfs:
            if pdf.get('po_match'):
                return pdf['url']
        
        # Fall back to first available
        return pdfs[0]['url']


def get_modulhandbuch_for_degree(degree_identity: Dict) -> Dict:
    """
    Main entry point: Get Modulhandbuch info for a degree identity.
    
    Args:
        degree_identity: Dict from BOSS scraper
        
    Returns:
        Dict with:
            - success: bool
            - pdf_url: str or None
            - pdf_list: List of available PDFs
            - route_info: Routing configuration used
    """
    router = ModulhandbuchRouter(degree_identity)
    
    result = {
        'success': False,
        'pdf_url': None,
        'pdf_list': [],
        'route_info': {
            'normalized_subject': router.normalized_subject,
            'degree_type': router.degree_type,
            'po_version': router.po_version,
            'page_url': router.get_modulhandbuch_page_url()
        }
    }
    
    # Get PDF list from dynamic discovery (for display purposes)
    pdf_list = router.fetch_pdf_urls()
    result['pdf_list'] = pdf_list
    
    # Get best PDF URL (checks config first, then dynamic list)
    best_url = router.get_best_pdf_url()
    if best_url:
        result['success'] = True
        result['pdf_url'] = best_url
    
    return result
