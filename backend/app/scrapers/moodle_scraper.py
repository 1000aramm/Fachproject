"""
Moodle Deadline Scraper
Optimized for speed and reliability.
"""
import logging
import time
import os
import re
from datetime import datetime
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
from bs4 import BeautifulSoup
import dateparser

import urllib.parse

from app.utils.webdriver_utils import get_cached_driver_path, DEBUG_DIR

logger = logging.getLogger(__name__)

class MoodleScraper:
    def __init__(self, username, password, driver=None):
        self.username = username
        self.password = password
        self.driver = driver
        self.wait = None
        
        if not os.path.exists(DEBUG_DIR):
            os.makedirs(DEBUG_DIR, exist_ok=True)

    def _dump_debug_info(self, prefix):
        """Save screenshot and HTML for debugging."""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            if self.driver:
                screenshot_path = os.path.join(DEBUG_DIR, f"{prefix}_{timestamp}.png")
                html_path = os.path.join(DEBUG_DIR, f"{prefix}_{timestamp}.html")
                self.driver.save_screenshot(screenshot_path)
                logger.info(f"Saved screenshot to {screenshot_path}")
                with open(html_path, 'w', encoding='utf-8') as f:
                    f.write(self.driver.page_source)
                logger.info(f"Saved HTML to {html_path}")
        except Exception as e:
            logger.warning(f"Failed to dump debug info: {e}")

    def _setup_driver(self):
        """Set up Chrome in headless mode with performance optimizations."""
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1280,720")
        
        # Performance Flag: Disable images
        chrome_options.add_argument("--blink-settings=imagesEnabled=false")
        
        # Performance Flag: Reuse user data dir for session caching
        chrome_options.add_argument("--user-data-dir=" + DEBUG_DIR)
        
        try:
            # Shared Driver Path
            driver_path = get_cached_driver_path()
            logger.debug(f"Using cached driver path: {driver_path}")
            
            service = Service(driver_path)
            self.driver = webdriver.Chrome(service=service, options=chrome_options)
            self.wait = WebDriverWait(self.driver, 10)
        except Exception as e:
            logger.error(f"Failed to setup driver: {e}")
            raise

    def login(self):
        """Log in to Moodle via TU Dortmund SSO."""
        if not self.driver:
            self._setup_driver()
        elif not self.wait:
            self.wait = WebDriverWait(self.driver, 10)

        logger.info("Navigating to Moodle login page...")
        self.driver.get("https://moodle.tu-dortmund.de/login/index.php")
        
        # 1. Check if already logged in
        if "moodle.tu-dortmund.de/my" in self.driver.current_url:
            logger.info("Session resumed (already logged in)")
            return True

        # 2. Click UniAccount
        try:
            uni_btn = self.wait.until(EC.element_to_be_clickable(
                (By.XPATH, "//a[contains(text(), 'UniAccount') or contains(@href, 'itmc')]")
            ))
            uni_btn.click()
            logger.info("Clicked UniAccount button")
        except Exception as e:
            logger.debug(f"UniAccount button not found, checking if on SSO page: {e}")

        # 3. Handle SSO
        try:
            self.wait.until(lambda d: "sso.itmc" in d.current_url or "moodle.tu-dortmund.de/my" in d.current_url)
            
            if "moodle.tu-dortmund.de/my" in self.driver.current_url:
                return True
                
            logger.info("Entering credentials on SSO...")
            user_input = self.wait.until(EC.visibility_of_element_located(
                (By.CSS_SELECTOR, "input#username, input#idToken1")
            ))
            user_input.clear()
            user_input.send_keys(self.username)
            
            pass_input = self.driver.find_element(By.CSS_SELECTOR, "input[type='password'], input#idToken2")
            pass_input.clear()
            pass_input.send_keys(self.password)
            
            self.driver.find_element(By.CSS_SELECTOR, "input[type='submit'], button[type='submit'], #loginButton_0").click()
            
            # Wait for redirect (timeout indicates potential failure)
            time.sleep(3)  # Give SSO time to process
            
            # Handle TOTP registration page if it appears
            # This page asks about second factor registration - we click "Login without registration"
            try:
                skip_totp_btn = self.driver.find_element(By.CSS_SELECTOR, "input#idToken4_1[value='Login without registration'], input[value='Login without registration']")
                if skip_totp_btn.is_displayed():
                    skip_totp_btn.click()
                    logger.info("Clicked 'Login without registration' to skip TOTP setup")
                    time.sleep(2)  # Wait for redirect after clicking
            except Exception as totp_e:
                logger.debug(f"TOTP registration page not shown or already bypassed: {totp_e}")
            
            # Check for common authentication failure indicators
            page_source_lower = self.driver.page_source.lower()
            current_url = self.driver.current_url.lower()
            
            # List of error indicators that suggest failed login
            error_indicators = [
                "login failed",
                "anmeldung fehlgeschlagen", 
                "authentication failed",
                "invalid credentials",
                "ungültige anmeldedaten",
                "falsches passwort",
                "wrong password",
                "incorrect password",
                "benutzername oder passwort",
                "username or password",
                "anmeldung nicht erfolgreich",
                "login unsuccessful",
                "zugriff verweigert",
                "access denied"
            ]
            
            for indicator in error_indicators:
                if indicator in page_source_lower:
                    logger.warning(f"SSO Login failed: Found error indicator '{indicator}'")
                    self._dump_debug_info("moodle_auth_failed")
                    return False
            
            # Check if still on SSO page (hasn't redirected properly)
            if "sso.itmc" in current_url:
                # If still on SSO and username field is visible, login likely failed
                try:
                    user_field = self.driver.find_element(By.CSS_SELECTOR, "input#username, input#idToken1")
                    if user_field.is_displayed():
                        logger.warning("SSO Login failed: Still on SSO page with visible login form")
                        self._dump_debug_info("moodle_still_on_sso")
                        return False
                except: 
                    pass  # If username field not found, might be redirecting
            
            # Verify we actually reached Moodle dashboard
            try:
                self.wait.until(EC.url_contains("moodle.tu-dortmund.de"))
                
                # Final check - are we on dashboard or redirected elsewhere?
                if "moodle.tu-dortmund.de/my" in self.driver.current_url or "moodle.tu-dortmund.de/login/index.php" not in self.driver.current_url:
                    logger.info("Successfully authenticated to Moodle")
                    return True
                else:
                    logger.warning("SSO Login failed: Redirected back to login page")
                    return False
            except:
                logger.warning("SSO Login failed: Timeout waiting for Moodle redirect")
                self._dump_debug_info("moodle_timeout")
                return False
                
        except Exception as e:
            logger.error(f"Login failed: {e}")
            self._dump_debug_info("moodle_login_err")
            return False

    def extract_deadlines(self):
        """Extract deadlines from Moodle timeline."""
        logger.info("Extracting deadlines...")
        if "moodle.tu-dortmund.de/my" not in self.driver.current_url:
            self.driver.get("https://moodle.tu-dortmund.de/my/")
            
        try:
            # 1. Try to set filter to 'All' to see all future deadlines
            # We use a longer wait for the timeline block specifically in containers
            try:
                self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "[data-region='timeline'], .block_timeline, #instance-xml-declaration-timeline")))
                
                filter_btn = self.wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "[id^='timeline-day-filter']")))
                filter_btn.click()
                all_filter = self.wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "[data-filtername='all']")))
                all_filter.click()
                time.sleep(2) # Content refresh wait
                logger.info("Set timeline filter to 'All'")
            except Exception as e:
                logger.debug(f"Could not set timeline filter (maybe already set or different layout): {e}")

            # Final check for timeline region
            self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "[data-region='timeline'], .block_timeline")))
        except:
            logger.warning("Timeline region not found after wait. Proceeding with full page scan.")

        deadlines = []
        seen_urls = set()
        soup = BeautifulSoup(self.driver.page_source, 'html.parser')
        
        # Look for activity links in timeline
        links = soup.find_all('a', href=re.compile(r'mod/(assign|quiz|forum)'))
        for link in links:
            try:
                name = link.get_text(strip=True)
                if not name: continue
                
                # Broad text to search for dates (prioritize aria-label as it's often very precise)
                aria_label = link.get('aria-label', '')
                
                # Filter out generic 'Anzeigen' or 'Abgeben' links if they exist
                if name.lower() in ['anzeigen', 'abgeben', 'details', 'submission', 'aufgabenlösung hinzufügen']: 
                    # Try to find a better label nearby
                    parent_row = link.find_parent(['div', 'li'], class_=re.compile(r'event|activity|list-group-item'))
                    if parent_row:
                        name_elem = parent_row.find(['h6', 'span'], class_=re.compile(r'event-name|activityname')) or parent_row.find('strong')
                        if name_elem: name = name_elem.get_text(strip=True)

                parent = link.find_parent(['div', 'li'], class_=re.compile(r'event|activity|list-group-item'))
                if not parent: continue
                
                course = ""
                # Try to find course name in parent or surrounding
                course_elem = parent.find(['small', 'span'], class_=re.compile(r'course|text-muted|event-name'))
                if course_elem:
                    # Sometimes course name has a prefix or breadcrumb
                    course = course_elem.get_text(strip=True).replace("Kurs: ", "").strip()
                
                # Improved Date parsing
                due_date = ""
                
                # We combine aria-label and visible text for maximum info
                search_text = f"{aria_label} {parent.get_text(' ', strip=True)}"
                
                # Remove the name of the activity from the text to avoid confusing the parser
                cleaned_text = search_text.replace(name, "").strip()
                
                # Strategy 1: Look for specific date patterns in the text
                date_pattern = r'(\d{1,2}\.?(?:\s+|[.-])(?:Jan|Feb|Mär|Apr|Mai|Jun|Jul|Aug|Sep|Okt|Nov|Dez)[a-z]*\s+\d{4}|\d{1,2}\.\d{1,2}\.\d{2,4})'
                match = re.search(date_pattern, cleaned_text, re.IGNORECASE)
                
                raw_date = None
                if match:
                    raw_date = match.group(1)
                    time_match = re.search(r'(\d{1,2}:\d{2})', cleaned_text)
                    if time_match:
                        raw_date += f" {time_match.group(1)}"
                
                dt = None
                if raw_date:
                    dt = dateparser.parse(raw_date, languages=['de', 'en'], settings={'DATE_ORDER': 'DMY'})
                
                if not dt:
                    # Strategy 2: Direct parse of cleaned text (handles "morgen", "in 5 Tagen", etc.)
                    dt = dateparser.parse(cleaned_text, languages=['de', 'en'], settings={
                        'PREFER_DATES_FROM': 'future',
                        'DATE_ORDER': 'DMY'
                    })

                if dt:
                    if dt.year > datetime.now().year + 50:
                        dt = dt.replace(year=dt.year - 100)
                    due_date = dt.isoformat()

                # Normalize URL for deduplication (remove action parameters)
                raw_url = link.get('href', '')
                parsed_url = urllib.parse.urlparse(raw_url)
                # Keep only 'id' parameter for normalization
                params = urllib.parse.parse_qs(parsed_url.query)
                clean_params = {k: v for k, v in params.items() if k == 'id'}
                normalized_url = urllib.parse.urlunparse(parsed_url._replace(query=urllib.parse.urlencode(clean_params, doseq=True)))
                
                if normalized_url in seen_urls:
                    continue
                
                deadlines.append({
                    "activity_name": name,
                    "course_name": course,
                    "due_date": due_date,
                    "url": raw_url
                })
                seen_urls.add(normalized_url)
            except: continue
            
        logger.info(f"Scraped {len(deadlines)} deadlines")
        return deadlines

    def get_deadlines(self, close_driver=True):
        """Fetch deadlines from start to finish."""
        try:
            if not self.driver:
                self._setup_driver()
            
            if self.login():
                deadlines = self.extract_deadlines()
                return {"success": True, "deadlines": deadlines}
            return {"success": False, "error": "Authentication failed"}
        except Exception as e:
            logger.error(f"Moodle error: {e}")
            return {"success": False, "error": str(e)}
        finally:
            if close_driver and self.driver:
                self.driver.quit()
                self.driver = None
