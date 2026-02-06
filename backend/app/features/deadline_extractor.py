import logging
import json
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# Pydantic Models for Structured Output
class DeadlineItem(BaseModel):
    title: str = Field(description="The title or name of the text/exam/deadline")
    date: str = Field(description="The due date in ISO 8601 format (YYYY-MM-DD)")
    type: str = Field(description="Type of deadline: 'exam', 'assignment', 'project', 'other'")
    description: Optional[str] = Field(description="Brief description")

class SyllabusDeadlines(BaseModel):
    deadlines: List[DeadlineItem]

class DeadlineExtractor:
    def __init__(self, client: genai.Client):
        self.client = client
        self.model_id = "models/gemini-2.0-flash"

    async def extract_from_file(self, file_content: bytes, mime_type: str) -> List[dict]:
        """
        Extracts deadlines from a syllabus file (PDF/Image) using Gemini structured output.
        Returns a list of dicts with Python datetime objects.
        """
        logger.info(f"Extracting deadlines from file type: {mime_type}")
        
        prompt = """
        Analyze this course syllabus/document and extract all important dates and deadlines.
        Focus on exams, assignments, project submissions, and key academic dates.
        Return the data in valid JSON format matching the schema.
        Ensure dates are in YYYY-MM-DD format. If no year is specified, assume the upcoming academic year.
        如果是Date Range (e.g., Oct 10-12), use the START date.
        """
        
        try:
            # Create content part for the file
            # For extraction, we might not need cache if it's a single file processing
            # We can pass bytes directly if small enough, or upload. 
            # For safety with larger files (syllabi can be large), let's assume valid inline data if < 20MB,
            # but user said 20MB limit for audio. PDF text extraction is usually fine inline.
            
            response = await self.client.aio.models.generate_content(
                model=self.model_id,
                contents=[
                    types.Content(
                        role="user",
                        parts=[
                            types.Part(text=prompt),
                            types.Part(inline_data=types.Blob(
                                mime_type=mime_type,
                                data=file_content
                            ))
                        ]
                    )
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=SyllabusDeadlines
                )
            )
            
            # Parse result
            data = response.parsed # Should be SyllabusDeadlines instance
            
            # Post-processing to convert str -> datetime
            valid_deadlines = []
            if data and data.deadlines:
                for item in data.deadlines:
                    try:
                        dt = datetime.strptime(item.date, "%Y-%m-%d")
                        valid_deadlines.append({
                            "title": item.title,
                            "date": dt,
                            "type": item.type,
                            "description": item.description
                        })
                    except ValueError:
                        logger.warning(f"Skipping invalid date format: {item.date}")
                        continue
                        
            logger.info(f"Extracted {len(valid_deadlines)} deadlines.")
            return valid_deadlines

        except Exception as e:
            logger.error(f"Deadline extraction failed: {e}")
            return []
