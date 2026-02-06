import logging
from typing import List, Dict, Optional
from datetime import datetime, timezone
from app.services.gemini_engine import get_supabase

logger = logging.getLogger(__name__)

class AcademicService:
    async def save_deadlines(self, user_uuid: str, deadlines: List[Dict]):
        """Persists Moodle deadlines to database."""
        if not deadlines:
            return
            
        supabase = await get_supabase()
        logger.info(f"Saving {len(deadlines)} deadlines for user {user_uuid}")
        
        for d in deadlines:
            try:
                # Upsert based on user_id, activity_name, and due_date
                # We need to ensure due_date is handled correctly if null
                if not d.get("activity_name") or not d.get("due_date"):
                    continue
                    
                await supabase.table("student_deadlines").upsert({
                    "user_id": user_uuid,
                    "activity_name": d["activity_name"],
                    "course_name": d.get("course_name"),
                    "due_date": d.get("due_date"),
                    "url": d.get("url")
                }, on_conflict="user_id, activity_name, due_date").execute()
            except Exception as e:
                logger.error(f"Error during student_deadlines upsert: {e}")
                if hasattr(e, 'message'): logger.error(f"Supabase Error Message: {e.message}")
                logger.warning(f"Failed to upsert deadline '{d.get('activity_name')}': {e}")

    async def save_grades(self, user_uuid: str, grades: List[Dict], summary_data: Dict):
        """Persists BOSS grades and profile summary to database."""
        supabase = await get_supabase()
        logger.info(f"Saving grades and profile for user {user_uuid}")
        
        # 1. Update Profile
        try:
            await supabase.table("academic_profiles").upsert({
                "user_id": user_uuid,
                "total_ects": float(summary_data.get("total_ects", summary_data.get("total_credits", 0))),
                "average_grade": summary_data.get("average_grade", summary_data.get("current_gpa")),
                "best_grade": summary_data.get("best_grade"),
                "degree_program": summary_data.get("degree_program"),
                "updated_at": datetime.now(timezone.utc).isoformat()
            }).execute()
        except Exception as e:
            logger.error(f"Error during academic_profiles upsert: {e}")
            if hasattr(e, 'message'): logger.error(f"Supabase Error Message: {e.message}")
            logger.warning(f"Failed to update academic profile for {user_uuid}: {e}")

        # 2. Save Grades
        if grades:
            for g in grades:
                try:
                    if not g.get("title") and not g.get("exam_title"):
                        continue
                        
                    await supabase.table("student_grades").upsert({
                        "user_id": user_uuid,
                        "exam_title": g.get("title", g.get("exam_title")),
                        "grade": float(g["grade"]) if g.get("grade") is not None and g.get("grade") != "" else None,
                        "credits": float(g["credits"]) if g.get("credits") is not None and g.get("credits") != "" else 0.0,
                        "status": g.get("status"),
                        "is_passed": g.get("passed", False),
                        "semester": g.get("semester")
                    }, on_conflict="user_id, exam_title, semester").execute()
                except Exception as e:
                    logger.error(f"Error during student_grades upsert: {e}")
                    if hasattr(e, 'message'): logger.error(f"Supabase Error Message: {e.message}")
                    logger.warning(f"Failed to upsert grade '{g.get('title')}': {e}")

    async def get_academic_summary(self, user_uuid: str) -> str:
        """Constructs a text summary for Gemini context."""
        try:
            supabase = await get_supabase()
            
            # Fetch profile
            profile_resp = await supabase.table("academic_profiles").select("*").eq("user_id", user_uuid).maybe_single().execute()
            profile = profile_resp.data if profile_resp.data else {}
            
            # Fetch deadlines (future only)
            now = datetime.now(timezone.utc).isoformat()
            deadlines_resp = await supabase.table("student_deadlines").select("*").eq("user_id", user_uuid).gte("due_date", now).order("due_date").limit(10).execute()
            deadlines = deadlines_resp.data if deadlines_resp.data else []
            
            # Fetch grades (recent achievements)
            grades_resp = await supabase.table("student_grades").select("*").eq("user_id", user_uuid).order("created_at", desc=True).limit(15).execute()
            grades = grades_resp.data if grades_resp.data else []
            
            summary = "[ACADEMIC CONTEXT]\n"
            summary += f"Today's Date: {datetime.now(timezone.utc).strftime('%A, %B %d, %Y')}\n"
            
            if profile:
                summary += f"- Program: {profile.get('degree_program', 'N/A')}\n"
                summary += f"- Overall ECTS: {profile.get('total_ects', 0)}\n"
                summary += f"- Average Grade: {profile.get('average_grade', 'N/A')}\n"
                summary += f"- Best Grade: {profile.get('best_grade', 'N/A')}\n"

            if grades:
                summary += "- Recent Grades / Passed Modules:\n"
                for g in grades:
                    summary += f"  * {g['exam_title']}: {g.get('grade', 'N/A')} ({g.get('status', 'N/A')}, {g.get('credits', 0)} ECTS)\n"
                
            if deadlines:
                summary += "- Upcoming Deadlines:\n"
                for d in deadlines:
                    dt = datetime.fromisoformat(d['due_date'].replace('Z', '+00:00'))
                    summary += f"  * {d['activity_name']} ({d['course_name']}) due {dt.strftime('%d.%m.%Y %H:%M')}\n"
            else:
                summary += "- No upcoming deadlines found.\n"
            
            return summary
        except Exception as e:
            logger.error(f"Failed to generate academic summary: {e}")
            return f"[ACADEMIC CONTEXT]\nToday's Date: {datetime.now(timezone.utc).strftime('%A, %B %d, %Y')}\n(Could not load study data)"
