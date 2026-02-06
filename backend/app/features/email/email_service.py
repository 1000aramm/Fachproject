import imaplib
import smtplib
import ssl
import re
import email
from email.header import decode_header
from typing import List, Dict, Optional, Tuple

# Configuration Constants
IMAP_HOST = "unimail.tu-dortmund.de"
IMAP_PORT = 993
SMTP_HOST = "unimail.tu-dortmund.de"
SMTP_PORT = 465

def create_ssl_context() -> ssl.SSLContext:
    """
    Creates a secure SSL context. 
    Attempts to load default verify locations.
    """
    context = ssl.create_default_context()
    # If specific CA bundles are needed they would be loaded here.
    # On most modern Linux systems, T-TeleSec GlobalRoot Class 2 should be trusted by default.
    return context

def sanitize_content(text: str) -> str:
    """
    Sanitizes PII from the text content.
    - Removes 6-digit Matriculation numbers.
    - Removes IBANs.
    """
    if not text:
        return ""
    
    # Redact Matriculation numbers (exact 6 digits)
    text = re.sub(r'\b\d{6}\b', '[REDACTED_MATR_NR]', text)
    
    # Redact IBANs (Simplified Regex to catch common DE IBANs or generic ones)
    # DE followed by 20 digits is standard German IBAN
    text = re.sub(r'\bDE\d{2}\s?(\d{4}\s?){4}\d{2}\b', '[REDACTED_IBAN]', text, flags=re.IGNORECASE)
    # Generic IBAN-like structure protection
    text = re.sub(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b', '[REDACTED_IBAN]', text)
    
    return text

def connect_to_imap(username: str, password: str) -> imaplib.IMAP4_SSL:
    """
    Connects to the TU Dortmund IMAP server using SSL.
    """
    context = create_ssl_context()
    try:
        mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT, ssl_context=context)
        mail.login(username, password)
        return mail
    except imaplib.IMAP4.error as e:
        print(f"IMAP Connection Failed: {e}")
        raise AuthenticationError("Failed to login to IMAP server. Check credentials.")
    except Exception as e:
        print(f"IMAP Connection Error: {e}")
        raise ConnectionError(f"Could not connect to IMAP server: {e}")

def decode_mime_header(header_value: str) -> str:
    """Decodes MIME encoded headers (e.g. Subject)."""
    if not header_value:
        return ""
    decoded_list = decode_header(header_value)
    decoded_str = ""
    for content, encoding in decoded_list:
        if isinstance(content, bytes):
            if encoding:
                try:
                    decoded_str += content.decode(encoding)
                except LookupError:
                    decoded_str += content.decode('utf-8', errors='ignore')
            else:
                decoded_str += content.decode('utf-8', errors='ignore')
        else:
            decoded_str += str(content)
    return decoded_str

def get_body_from_message(msg) -> str:
    """Extracts plain text (preferred) or HTML body from email message."""
    body = ""
    html_body = ""
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition"))
            if content_type == "text/plain" and "attachment" not in content_disposition:
                try:
                    payload = part.get_payload(decode=True)
                    if payload:
                        body += payload.decode(errors='ignore')
                except:
                    pass
            elif content_type == "text/html" and "attachment" not in content_disposition:
                try:
                    payload = part.get_payload(decode=True)
                    if payload:
                        html_body += payload.decode(errors='ignore')
                except:
                    pass
    else:
        try:
           payload = msg.get_payload(decode=True)
           if payload:
               body += payload.decode(errors='ignore')
        except:
           pass
    
    # If no plain text, use HTML (clean tags if needed, but for now just pass text)
    if not body and html_body:
        # Simple regex to strip HTML tags for the stateless proxy
        body = re.sub('<[^<]+?>', '', html_body)
    
    return body.strip()

def fetch_headers(username: str, password: str, limit: int = 20) -> List[Dict]:
    """
    Fetches the last N emails from the inbox.
    Uses BODY.PEEK to ensure authentication is successful and emails remain 'Unseen'.
    """
    mail = connect_to_imap(username, password)
    
    try:
        mail.select("inbox")
        
        # Search for all messages
        status, messages = mail.search(None, "ALL")
        if status != "OK":
            return []

        mail_ids = messages[0].split()
        # Get last N ids
        latest_ids = mail_ids[-limit:]
        
        email_list = []
        
        # Fetch in reverse order (newest first)
        for i in reversed(latest_ids):
            # BODY.PEEK[] prevents marking as read
            # RFC822 fetches the whole raw message, useful for parsing standard py email lib
            status, msg_data = mail.fetch(i, "(BODY.PEEK[])")
            
            for response_part in msg_data:
                if isinstance(response_part, tuple):
                    msg = email.message_from_bytes(response_part[1])
                    
                    subject = decode_mime_header(msg["Subject"])
                    sender = decode_mime_header(msg["From"])
                    date = decode_mime_header(msg["Date"])
                    
                    # Sanitize body strictly for preview/processing if needed, 
                    # though prompt asked for 'fetch_headers', often snippet preview is useful.
                    # We will return basic structure.
                    
                    email_list.append({
                        "id": i.decode(),
                        "subject": log_safe_sanitize(subject),
                        "sender": log_safe_sanitize(sender),
                        "date": date
                    })
        
        return email_list
        
    finally:
        try:
            mail.logout()
        except:
            pass

def fetch_body(username: str, password: str, email_id: str) -> str:
    """
    Fetches and sanitizes the body of a specific email ID.
    Uses BODY.PEEK to keep the 'Unseen' status.
    """
    mail = connect_to_imap(username, password)
    
    try:
        mail.select("inbox")
        # Fetch the whole message (PEEK)
        status, msg_data = mail.fetch(email_id, "(BODY.PEEK[])")
        
        if status != "OK":
            return "[Error: Could not retrieve email body]"

        for response_part in msg_data:
            if isinstance(response_part, tuple):
                msg = email.message_from_bytes(response_part[1])
                body = get_body_from_message(msg)
                return log_safe_sanitize(body)
        
        return "[No content found]"
        
    finally:
        try:
            mail.logout()
        except:
            pass

def log_safe_sanitize(text: str) -> str:
    """Wrapper to sanitize PII for logging/returning headers."""
    return sanitize_content(text)

def send_email(username: str, password: str, to_email: str, subject: str, body: str):
    """
    Sends an email using SMTP over SSL (Port 465).
    """
    context = create_ssl_context()
    
    # Create the email object
    msg = email.message.Message()
    msg['Subject'] = subject
    msg['From'] = f"{username}@tu-dortmund.de" # Constructing typical usage, though sender might want custom FROM
    # Usually standard uni login matches the from address logic or uses alias. 
    # For now we use the email lib to format.
    
    # Better to use EmailMessage for modern python
    from email.message import EmailMessage
    msg = EmailMessage()
    msg.set_content(body)
    msg['Subject'] = subject
    # We don't know the exact email address alias, but usually it's username@tu-dortmund.de or set by user.
    # The prompt implies authenticating with UniAccount but doesn't strictly say sender email.
    # We will assume username is the UniID. 
    # IMPORTANT: Many servers reject if FROM doesn't match auth user.
    # We'll use the raw username for auth, but send header might need to be valid email.
    # Let's try simple construction or just pass what is needed.
    # For safety, let's just use the username if it looks like an email, else append domain.
    sender_email = username if "@" in username else f"{username}@tu-dortmund.de"
    msg['From'] = sender_email
    msg['To'] = to_email

    try:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context) as server:
            server.login(username, password)
            server.send_message(msg)
    except smtplib.SMTPAuthenticationError:
        raise AuthenticationError("SMTP Authentication failed.")
    except Exception as e:
        raise ConnectionError(f"Failed to send email: {e}")

class AuthenticationError(Exception):
    pass

class ConnectionError(Exception):
    pass
