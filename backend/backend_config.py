"""
Backend Configuration

Centralized configuration for the Ayla backend.
System instructions are now defined in their respective routers:
- assistant_router.py: ASSISTANT_SYSTEM_INSTRUCTION
- workspace_router.py: workspace_sys_instr
"""

import os

# Model Configuration
# We use gemini-2.0-flash for stability and better refusal handling
MODEL_NAME = "models/gemini-2.0-flash"

