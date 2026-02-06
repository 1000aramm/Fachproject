"""
Degree Audit Logic - Performs set difference calculation between 
curriculum requirements and completed exams.

Compares student's passed exams from BOSS with curriculum requirements
from Modulhandbuch to calculate missing modules and remaining credits.
"""

import logging
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict

logger = logging.getLogger(__name__)


@dataclass
class MissingModule:
    """A module that still needs to be completed."""
    module_id: str
    name: str
    ects: int
    category: str


@dataclass
class ElectiveStatus:
    """Status of elective credit requirements."""
    area_name: str
    required_ects: int
    completed_ects: int
    remaining_ects: int
    suggestions: List[str]


@dataclass
class AuditResult:
    """Complete degree audit result."""
    status: str  # "Complete", "In Progress", "Behind"
    total_credits_earned: int
    total_credits_required: int
    progress_percentage: float
    missing_mandatory: List[MissingModule]
    elective_status: List[ElectiveStatus]
    completed_modules: List[Dict]


def normalize_module_id(module_id: str) -> str:
    """
    Normalize module ID for comparison.
    Handles variations like "INF-60300", "60300", "INF 60300".
    """
    if not module_id:
        return ""
    
    # Remove common prefixes and normalize
    normalized = module_id.upper()
    normalized = normalized.replace("-", "").replace(" ", "")
    
    # Extract just the numeric part if present
    import re
    numbers = re.findall(r'\d+', normalized)
    if numbers:
        return numbers[0]
    
    return normalized


def perform_audit(
    passed_exams: List[Dict],
    curriculum: Dict,
    degree_identity: Dict
) -> Dict:
    """
    Perform degree audit by comparing passed exams to curriculum.
    
    Args:
        passed_exams: List of exam dicts from BOSS scraper
            Each should have: title, exam_id, grade, credits, status
        curriculum: Parsed curriculum from ModulhandbuchParser
            Should have: mandatory_modules, elective_areas, total_ects
        degree_identity: Degree info from BOSS
            Should have: degree_type, degree_subject, po_version
    
    Returns:
        Dict with audit results
    """
    
    # Build set of passed exam IDs (normalized)
    passed_ids = set()
    passed_by_id = {}
    total_earned = 0
    
    for exam in passed_exams:
        # Check if passed (grade <= 4.0 for German grading, or status == "bestanden")
        grade = exam.get('grade')
        status = exam.get('status', '').lower()
        
        is_passed = False
        # German grading: 1.0 to 4.0 is passed, 5.0 is failed.
        if grade and isinstance(grade, (int, float)):
             if grade <= 4.0:
                 is_passed = True
        
        # If passed via grade check, we are good.
        # If not (e.g. grade is 5.0), we should NOT check status unless stricter.
        # But sometimes grade is missing.
        
        # Proper Logic:
        # 1. If 'nicht bestanden' or 'failed' in status -> False (regardless of grade, usually)
        # 2. Else if grade <= 4.0 -> True
        # 3. Else if 'bestanden' in status -> True
        
        if 'nicht bestanden' in status or 'failed' in status:
            is_passed = False
        elif grade and isinstance(grade, (int, float)) and grade <= 4.0:
            is_passed = True
        elif 'bestanden' in status or 'passed' in status:
            is_passed = True
        
        if is_passed:
            exam_id = normalize_module_id(exam.get('exam_id', ''))
            if exam_id:
                passed_ids.add(exam_id)
                passed_by_id[exam_id] = exam
                total_earned += exam.get('credits', 0) or 0
    
    logger.info(f"Found {len(passed_ids)} passed exams with {total_earned} ECTS")
    
    # Get mandatory modules from curriculum
    mandatory_modules = curriculum.get('mandatory_modules', [])
    mandatory_ids = set()
    mandatory_by_id = {}
    
    for module in mandatory_modules:
        mod_id = normalize_module_id(module.get('module_id', ''))
        if mod_id:
            mandatory_ids.add(mod_id)
            mandatory_by_id[mod_id] = module
    
    # Calculate missing mandatory modules
    missing_ids = mandatory_ids - passed_ids
    missing_mandatory = []
    
    for mod_id in missing_ids:
        module = mandatory_by_id.get(mod_id, {})
        missing_mandatory.append(MissingModule(
            module_id=module.get('module_id', mod_id),
            name=module.get('name', 'Unknown Module'),
            ects=module.get('ects', 0),
            category='Pflicht'
        ))
    
    logger.info(f"Missing {len(missing_mandatory)} mandatory modules")
    
    # Calculate elective status
    elective_areas = curriculum.get('elective_areas', {})
    elective_status = []
    
    for area_name, required_ects in elective_areas.items():
        # For now, assume all non-mandatory passed credits count as electives
        # In a more sophisticated version, we'd match by area
        completed_ects = 0  # Would need better matching
        
        elective_status.append(ElectiveStatus(
            area_name=area_name,
            required_ects=required_ects,
            completed_ects=completed_ects,
            remaining_ects=max(0, required_ects - completed_ects),
            suggestions=[]  # Would need to populate from available modules
        ))
    
    # Calculate overall status
    total_required = curriculum.get('total_ects', 180)
    progress = (total_earned / total_required * 100) if total_required > 0 else 0
    
    if total_earned >= total_required and len(missing_mandatory) == 0:
        status = "Complete"
    elif progress >= 50:
        status = "In Progress"
    else:
        status = "Behind"
    
    # Build result
    result = AuditResult(
        status=status,
        total_credits_earned=int(total_earned),
        total_credits_required=total_required,
        progress_percentage=round(progress, 1),
        missing_mandatory=missing_mandatory,
        elective_status=elective_status,
        completed_modules=[passed_by_id[pid] for pid in passed_ids if pid in passed_by_id]
    )
    
    return {
        'student_identity': {
            'degree_type': degree_identity.get('degree_type', 'Unknown'),
            'degree_subject': degree_identity.get('degree_subject', 'Unknown'),
            'po_version': degree_identity.get('po_version', 'Unknown'),
        },
        'audit_result': {
            'status': result.status,
            'total_credits_earned': result.total_credits_earned,
            'total_credits_required': result.total_credits_required,
            'progress_percentage': result.progress_percentage,
            'missing_mandatory': [asdict(m) for m in result.missing_mandatory],
            'elective_status': [asdict(e) for e in result.elective_status],
            'completed_count': len(result.completed_modules)
        }
    }


def quick_audit(passed_exams: List[Dict], degree_identity: Dict) -> Dict:
    """
    Perform a quick audit without PDF parsing.
    
    Uses default curriculum requirements based on degree type.
    """
    
    # Default requirements for common degrees
    DEFAULT_REQUIREMENTS = {
        'Bachelor': {
            'total_ects': 180,
            'mandatory_modules': [],
            'elective_areas': {'Wahlpflichtbereich': 30}
        },
        'Master': {
            'total_ects': 120,
            'mandatory_modules': [],
            'elective_areas': {'Wahlpflichtbereich': 30}
        }
    }
    
    degree_type = degree_identity.get('degree_type', 'Bachelor')
    curriculum = DEFAULT_REQUIREMENTS.get(degree_type, DEFAULT_REQUIREMENTS['Bachelor'])
    
    return perform_audit(passed_exams, curriculum, degree_identity)
