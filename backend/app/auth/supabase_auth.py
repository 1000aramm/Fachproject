import os
import jwt
from typing import Optional, Dict, Any
from fastapi import HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv
import logging

load_dotenv()

logger = logging.getLogger(__name__)

# User must provide this in .env
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")

# Security scheme
security = HTTPBearer()

def get_jwt_secret() -> str:
    """
    Retrieves the Supabase JWT secret.
    Raises an error if not set, enforcing the requirement for stateless verification.
    """
    if not SUPABASE_JWT_SECRET:
        logger.error("SUPABASE_JWT_SECRET is missing from environment variables.")
        raise HTTPException(
            status_code=500, 
            detail="Server Authorization configuration error: Missing JWT Secret."
        )
    return SUPABASE_JWT_SECRET

def verify_supabase_token(credentials: HTTPAuthorizationCredentials = Security(security)) -> Dict[str, Any]:
    """
    Stateless Local Verification of Supabase JWT.
    Decodes and verifies the signature using the HS256 secret.
    Does NOT make a network call to Supabase Auth.
    """
    token = credentials.credentials
    secret = get_jwt_secret()
    
    try:
        # Supabase uses HS256 by default.
        # Audience is usually 'authenticated'.
        payload = jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
            options={"verify_exp": True}
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidAudienceError:
        raise HTTPException(status_code=401, detail="Invalid token audience")
    except jwt.InvalidSignatureError:
        raise HTTPException(status_code=401, detail="Invalid token signature")
    except jwt.DecodeError:
        raise HTTPException(status_code=401, detail="Could not decode token")
    except Exception as e:
        logger.error(f"JWT Verification failed: {str(e)}")
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")

def get_current_user_id(payload: Dict[str, Any] = Depends(verify_supabase_token)) -> str:
    """
    Extracts the user ID ('sub') from the verified token payload.
    """
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing user ID")
    return user_id
