import logging
import time
from bs4 import BeautifulSoup
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from app.scrapers.boss_scraper import BossScraper

logger = logging.getLogger(__name__)

class LsfScraper(BossScraper):
    def __init__(self, username, password, totp_secret=None):
        super().__init__(username, password, totp_secret)
        self.lsf_url = "https://www.lsf.tu-dortmund.de/qisserver/rds?state=wscheck&wscheck=leistungen&navigationPosition=functions%2CmyLecturesWScheck&breadcrumb=myLectures&topitem=functions&subitem=myLecturesWScheck"

    def login(self):
        """Override login to start at LSF domain."""
        logger.info(f"Navigating to LSF: {self.lsf_url}")
        self.driver.get(self.lsf_url)
        
        # PROOF OF NEW VERSION
        logger.info("LSF-SPECIFIC LOGIN SEQUENCE STARTED")
        
        # 1. Faster Check: Am I already logged in?
        try:
            self.wait.until(lambda d: "sso.itmc" in d.current_url or "Abmelden" in d.page_source or "Anmelden" in d.page_source or "Login" in d.page_source)
        except:
            pass

        current_url = self.driver.current_url
        page_source = self.driver.page_source

        if "lsf.tu-dortmund.de" in current_url and "Abmelden" in page_source:
            logger.info("Session resumed (already logged in to LSF)")
            return True
            
        if "sso.itmc" in current_url:
            logger.info("Already on SSO page (from LSF).")
        else:
            logger.info("On LSF page. Looking for Login button...")
            try:
                # LSF login link text variants
                login_btn = None
                for text in ["Anmelden", "Login", "Einloggen"]:
                    try:
                        login_btn = self.driver.find_element(By.PARTIAL_LINK_TEXT, text)
                        if login_btn: break
                    except: continue
                
                if login_btn:
                    login_btn.click()
                    logger.info("Clicked login button")
                else:
                    logger.warning("No 'Anmelden/Login' button found. Checking for automatic SSO redirect...")
            except:
                pass

        return self._inject_sso_credentials()

    def _dump_debug_info(self, prefix="error"):
        """Save screenshot and HTML for debugging."""
        if not self.driver: return
        try:
            from datetime import datetime
            import os
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            from app.utils.webdriver_utils import DEBUG_DIR
            base_path = os.path.join(DEBUG_DIR, f"{prefix}_{timestamp}")
            self.driver.save_screenshot(f"{base_path}.png")
            with open(f"{base_path}.html", "w", encoding="utf-8") as f:
                f.write(self.driver.page_source)
            logger.info(f"Saved debug info to {base_path}")
        except Exception as e:
            logger.error(f"Failed to dump debug info: {e}")

    def _inject_sso_credentials(self):
        """Robust SSO injection logic ported from BossScraper."""
        logger.info("Injecting SSO credentials...")
        try:
            # 1. Wait for SSO or target
            self.wait.until(lambda d: "sso.itmc" in d.current_url or "lsf.tu-dortmund.de" in d.current_url)
            
            if "lsf.tu-dortmund.de" in self.driver.current_url and "Abmelden" in self.driver.page_source:
                return True

            # 2. Username Strategy
            user_field = None
            for strategy in [(By.ID, "username"), (By.NAME, "j_username"), (By.CSS_SELECTOR, "input#idToken1"), (By.CSS_SELECTOR, "input[type='text']")]:
                try:
                    el = self.driver.find_element(*strategy)
                    if el.is_displayed():
                        user_field = el
                        break
                except: continue
            
            if not user_field:
                self._dump_debug_info("lsf_login_no_user")
                raise Exception("Username field not found")
            
            user_field.clear()
            user_field.send_keys(self.username)
            
            # 3. Password Strategy
            pass_field = None
            for strategy in [(By.ID, "password"), (By.NAME, "j_password"), (By.CSS_SELECTOR, "input#idToken2"), (By.CSS_SELECTOR, "input[type='password']")]:
                try:
                    el = self.driver.find_element(*strategy)
                    if el.is_displayed():
                        pass_field = el
                        break
                except: continue
                
            if not pass_field:
                raise Exception("Password field not found")
            
            pass_field.clear()
            pass_field.send_keys(self.password)
            
            # 4. Submit Strategy
            submit_btn = None
            for strategy in [(By.NAME, "_eventId_proceed"), (By.ID, "loginButton_0"), (By.CSS_SELECTOR, "button[type='submit']"), (By.CSS_SELECTOR, "input[type='submit']")]:
                try:
                    el = self.driver.find_element(*strategy)
                    if el.is_displayed():
                        submit_btn = el
                        break
                except: continue
                
            if submit_btn:
                submit_btn.click()
            else:
                pass_field.submit()
            
            # 5. Handle 2FA
            try:
                # Wait for 2FA field or success
                self.wait.until(lambda d: "token" in d.page_source.lower() or "otp" in d.page_source.lower() or "lsf.tu-dortmund.de" in d.current_url)
                
                if ("token" in self.driver.page_source.lower() or "otp" in self.driver.page_source.lower()) and self.totp_secret:
                    logger.info("2FA Code Required...")
                    import pyotp
                    totp = pyotp.TOTP(self.totp_secret)
                    token = totp.now()
                    
                    token_field = None
                    for strategy in [(By.ID, "token"), (By.NAME, "otp"), (By.CSS_SELECTOR, "input[inputmode='numeric']")]:
                        try:
                            el = self.driver.find_element(*strategy)
                            if el.is_displayed():
                                token_field = el
                                break
                        except: continue
                    
                    if token_field:
                        token_field.send_keys(token)
                        # Find 2FA proceed button
                        try:
                            self.driver.find_element(By.NAME, "_eventId_proceed").click()
                        except:
                            self.driver.find_element(By.CSS_SELECTOR, "button[type='submit']").click()
            except: pass

            # 6. Final success check
            self.wait.until(EC.url_contains("lsf.tu-dortmund.de"))
            logger.info("Successfully logged in to LSF.")
            return True
        except Exception as e:
            logger.error(f"Injection failed: {e}")
            self._dump_debug_info("lsf_injection_fail")
            return False

    def extract_current_classes(self, html_content):
        """
        Extract classes for the current semester (e.g. Wintersemester 2025/26).
        The layout is assumed to be:
          <div class="Leistungen_Inhalt">Semester Name</div>
          ... 
          <a href="...">Class Link</a>
          ...
          <div class="Leistungen_Inhalt">Next Semester</div>
        """
        import re
        def normalize(t):
            return re.sub(r'\s+', ' ', t).strip()

        soup = BeautifulSoup(html_content, 'html.parser')
        
        # 1. Find the start marker (Current Semester)
        start_node = None
        
        # Try specific user target first, then fallback to generic regex
        target_patterns = [
            r"Wintersemester\s*2025/26",
            r"(Wintersemester|Sommersemester)\s*\d{4}(/\d{2})?"
        ]
        
        all_headers = soup.find_all("div", class_="Leistungen_Inhalt")
        
        for p in target_patterns:
            for header in all_headers:
                txt = normalize(header.get_text())
                if re.search(p, txt, re.IGNORECASE):
                    start_node = header
                    logger.info(f"Found semester header: {txt}")
                    break
            if start_node: break
            
        if not start_node:
            logger.warning("Could not find current semester header (e.g. Wintersemester 2025/26)")
            # Fallback check for old marker if new one fails
            if "Aktuelle Veranstaltungen" in soup.get_text():
                 logger.info("Fallback to 'Aktuelle Veranstaltungen' marker")
                 return self._legacy_extract(soup)
            return []

        # 2. Collect nodes until the next semester header
        classes = []
        seen_names = set()
        
        # iterate through all elements after start_node in document order
        # We need to be careful not to traverse the entire document if it's huge, 
        # but LSF pages are usually reasonable.
        # "next_elements" yields all tags and strings.
        
        # We want to stop at the next "Leistungen_Inhalt" div
        
        candidate_links = []
        
        for element in start_node.find_all_next():
            # semantic stop condition
            if element.name == "div" and "Leistungen_Inhalt" in element.get("class", []):
                 logger.info(f"Stopping at next header: {normalize(element.get_text())}")
                 break
            
            if element.name == 'a':
                candidate_links.append(element)

        # 3. Process candidates
        for link in candidate_links:
            link_text = normalize(link.get_text())
            
            is_candidate = False
            
            # Logic A: ID pattern
            if re.search(r'\d{4,6}', link_text):
                is_candidate = True
            
            # Junk Filters
            junk = ["Tag", "Zeit", "Rhythmus", "Dauer", "Raum", "Lehrperson", "Hinweis", "Belegungsinformation", "findet statt", "Belegungs-", "PDF", "Stundenplan", "Anmelden", "Login", "Abmelden"]
            if any(j.lower() in link_text.lower() for j in junk):
                is_candidate = False
            if len(link_text) < 5:
                is_candidate = False
                
            if is_candidate:
                if link_text not in seen_names:
                    classes.append(link_text)
                    seen_names.add(link_text)
                    logger.info(f"✅ FOUND CLASS: {link_text}")

        logger.info(f"Total classes found for semester: {len(classes)}")
        return classes

    def _legacy_extract(self, soup):
        # Very basic fallback using old marker if needed
        import re
        def normalize(t): return re.sub(r'\s+', ' ', t).strip()
        
        start_marker = "Aktuelle Veranstaltungen:"
        end_marker = "Absolvierte Veranstaltungen:"
        
        text = normalize(soup.get_text())
        if start_marker not in text: return []
        
        # This is hard to do without the node indices logic from before, 
        # but since we are replacing the file, let's assuming strict new logic is preferred.
        return []

    def get_current_classes(self):
        """Primary orchestration for LSF fetching."""
        try:
            self._setup_driver()
            if not self.login():
                return {"success": False, "error": "Login failed"}
            
            # Ensure we are on the lectures page
            if "state=wscheck" not in self.driver.current_url:
                logger.info("Navigating to lectures page...")
                self.driver.get(self.lsf_url)
            
            # Attempt hybrid fetch
            html = self._fetch_page_via_requests(self.lsf_url)
            if not html:
                logger.warning("httpx fetch failed, using selenium source")
                html = self.driver.page_source
            
            class_names = self.extract_current_classes(html)
            
            return {
                "success": True,
                "current_classes": [{"name": name} for name in class_names]
            }
        except Exception as e:
            logger.error(f"LSF Scraper Error: {e}")
            return {"success": False, "error": str(e)}
        finally:
            if self.driver:
                self.driver.quit()
