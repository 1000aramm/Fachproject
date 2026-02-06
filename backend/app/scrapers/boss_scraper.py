import logging
import time
import pyotp
import json
from datetime import datetime
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from bs4 import BeautifulSoup
import httpx


import os

# Configure logging
logging.basicConfig(level=logging.INFO)
from app.utils.webdriver_utils import get_cached_driver_path, DEBUG_DIR

logger = logging.getLogger(__name__)


class BossScraper:
    def __init__(self, username, password, totp_secret=None):
        self.username = username
        self.password = password
        self.totp_secret = totp_secret
        self.driver = None
        self.wait = None
        
        if not os.path.exists(DEBUG_DIR):
            os.makedirs(DEBUG_DIR, exist_ok=True)

    def _dump_debug_info(self, prefix="error"):
        if not self.driver: return
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_path = os.path.join(DEBUG_DIR, f"{prefix}_{timestamp}")
        
        # Save Screenshot
        try:
            self.driver.save_screenshot(f"{base_path}.png")
            logger.info(f"Saved screenshot to {base_path}.png")
        except Exception as e:
            logger.error(f"Failed to save screenshot: {e}")
            
        # Save HTML
        try:
            with open(f"{base_path}.html", "w", encoding="utf-8") as f:
                f.write(self.driver.page_source)
            logger.info(f"Saved HTML to {base_path}.html")
        except Exception as e:
            logger.error(f"Failed to save HTML: {e}")


    def _setup_driver(self):
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service
        from webdriver_manager.chrome import ChromeDriverManager
        import os

        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1280,720")
        
        # Performance Flag: Disable images
        chrome_options.add_argument("--blink-settings=imagesEnabled=false")
        
        # Performance Flag: Reuse user data dir for session caching
        # We use a subfolder in DEBUG_DIR for BOSS specifically
        boss_session_dir = os.path.join(DEBUG_DIR, "boss_session")
        if not os.path.exists(boss_session_dir):
            os.makedirs(boss_session_dir, exist_ok=True)
        chrome_options.add_argument(f"--user-data-dir={boss_session_dir}")
        
        # User Agent for consistency
        chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

        try:
            # Shared Driver Path
            driver_path = get_cached_driver_path()
            logger.debug("Using cached ChromeDriver path from utility module")

            service = Service(driver_path)
            self.driver = webdriver.Chrome(service=service, options=chrome_options)
            self.wait = WebDriverWait(self.driver, 10) # Optimized timeout
        except Exception as e:
            logger.error(f"Failed to setup driver: {e}")
            raise

    def login(self):
        logger.info("Navigating to BOSS...")
        self.driver.get("https://www.boss.tu-dortmund.de/")
        
        # 1. Faster Check: Am I already logged in or on SSO?
        # Use a short wait for the URL/Page to stabilize
        try:
            self.wait.until(lambda d: "sso.itmc" in d.current_url or "menue=n" in d.page_source or "Anmelden" in d.page_source)
        except:
            pass

        current_url = self.driver.current_url
        page_source = self.driver.page_source

        if "boss.tu-dortmund.de" in current_url and "menue=n" in page_source:
            logger.info("Session resumed (already logged in to BOSS)")
            return True
            
        if "sso.itmc" in current_url:
            logger.info("Already on SSO page.")
        else:
            logger.info("On BOSS landing page. Looking for Login button...")
            # Try to find a Login link/button with a VERY short timeout
            try:
                # Use find_elements to check existence without waiting if possible, 
                # or a very short explicit wait.
                short_wait = WebDriverWait(self.driver, 2)
                login_btn = short_wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Anmelden")))
                login_btn.click()
                logger.info("Clicked 'Anmelden'")
            except:
                try:
                    short_wait = WebDriverWait(self.driver, 1)
                    login_btn = short_wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Login")))
                    login_btn.click()
                    logger.info("Clicked 'Login'")
                except:
                    logger.warning("Could not find 'Anmelden' or 'Login' buttons within short timeout. Final SSO check...")
            
            # Final check if we reached SSO
            try:
                self.wait.until(EC.url_contains("sso.itmc"))
            except TimeoutException:
                 if "sso.itmc" not in self.driver.current_url:
                     logger.warning("Still not on SSO. Proceeding to check for credential fields anyway...")

        logger.info(f"Current URL: {self.driver.current_url}")

        # Step 2: Credential Injection (Robust)
        logger.info("Injecting credentials...")
        
        # Robust Username Search
        username_field = None
        strategies = [
            (By.ID, "username"),
            (By.NAME, "j_username"),
            (By.CSS_SELECTOR, "input[type='text']"),
            (By.CSS_SELECTOR, "input[type='email']")
        ]
        
        for by, val in strategies:
            try:
                username_field = self.driver.find_element(by, val)
                if username_field.is_displayed():
                    break
            except:
                continue
                
        if not username_field:
            logger.error(f"Could not find username field. Source: {self.driver.page_source[:500]}")
            raise Exception("Username field not found")

        username_field.clear()
        username_field.send_keys(self.username)
        
        # Robust Password Search
        password_field = None
        p_strategies = [
            (By.ID, "password"),
            (By.NAME, "j_password"),
            (By.CSS_SELECTOR, "input[type='password']")
        ]
        
        for by, val in p_strategies:
            try:
                password_field = self.driver.find_element(by, val)
                if password_field.is_displayed():
                    break
            except:
                continue
                
        if not password_field:
            raise Exception("Password field not found")
            
        password_field.clear()
        password_field.send_keys(self.password)
        
        # Robust Submit Button
        submit_btn = None
        s_strategies = [
            (By.NAME, "_eventId_proceed"),
            (By.CSS_SELECTOR, "button[type='submit']"),
            (By.CSS_SELECTOR, "input[type='submit']"),
            (By.XPATH, "//button[contains(text(), 'Login') or contains(text(), 'Anmelden')]")
        ]
        
        for by, val in s_strategies:
            try:
                submit_btn = self.driver.find_element(by, val)
                if submit_btn.is_displayed():
                    break
            except:
                continue
                
        if submit_btn:
            submit_btn.click()
        else:
             # Try hitting enter on password field
             password_field.submit()
        
        # Step 3: Handle 2FA
        # Wait for either error, 2FA, or redirect back to BOSS
        try:
            self.wait.until(lambda d: "error" in d.page_source.lower() or "fehlgeschlagen" in d.page_source.lower() or 
                           "sso.itmc" in d.current_url or "boss.tu-dortmund.de" in d.current_url)
        except:
            pass

        page_source = self.driver.page_source.lower()
        
        # Check for error
        if "login failed" in page_source or "fehlgeschlagen" in page_source:
             raise Exception("Invalid Credentials")

        if "sso.itmc" in self.driver.current_url and any(x in page_source for x in ["one-time password", "second factor", "zweiter faktor", "sicherheitstoken", "security token"]):
            logger.info("2FA Challenge detected.")
            if not self.totp_secret:
                raise Exception("2FA required but no TOTP secret provided.")
            
            totp = pyotp.TOTP(self.totp_secret)
            token = totp.now()
            logger.info("Generated TOTP token.")
            
            # Robust Token Input Field
            token_input = None
            t_strategies = [
                (By.ID, "token"),
                (By.NAME, "otp"),
                (By.CSS_SELECTOR, "input[type='text'][inputmode='numeric']"), # Common for OTP
                (By.CSS_SELECTOR, "input[type='text']") # Fallback
            ]
            
            for by, val in t_strategies:
                try:
                    token_input = self.driver.find_element(by, val)
                    if token_input.is_displayed():
                        break
                except:
                    continue
            
            if not token_input:
                raise Exception("2FA token input field not found.")

            token_input.clear()
            token_input.send_keys(token)
            
            # Find submit for 2FA
            try:
                verify_btn = self.driver.find_element(By.NAME, "_eventId_proceed")
            except:
                verify_btn = self.driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                
            verify_btn.click()
            # Wait for redirect after 2FA
            try:
                self.wait.until(EC.url_contains("boss.tu-dortmund.de"))
            except:
                pass
            
        # Step 4: Verification
        try:
            # We might still be on SSO if something failed, or back on BOSS
            current_url = self.driver.current_url
            if "boss.tu-dortmund.de" in current_url:
                 logger.info("Returned to BOSS domain.")
            else:
                 # Wait a bit more
                 self.wait.until(EC.url_contains("boss.tu-dortmund.de"))
                 logger.info("Returned to BOSS domain (after wait).")

            # Check for maintenance
            if "Wartungsarbeiten" in self.driver.page_source:
                raise Exception("BOSS is currently down for maintenance.")
        except TimeoutException:
            logger.error("Failed to return to BOSS after login.")
            logger.error(f"Current URL: {self.driver.current_url}")
            logger.error(f"Page Title: {self.driver.title}")
            raise Exception("Authentication failed or redirect timeout.")

    def navigate_to_grades(self):
        logger.info("Navigating to transcripts...")
        # Link 1: Prüfungsverwaltung / Exam Administration
        try:
            link1 = self.wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Prüfungsverwaltung")))
        except:
            try:
                 link1 = self.wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Exam Administration")))
            except:
                 # Depending on language settings
                 link1 = self.wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "a[href*='menue=n']"))) # generic heuristic if text fails
        
        link1.click()
        
        # Link 2: Notenspiegel / Grades
        try:
            link2 = self.wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Notenspiegel")))
        except:
            try:
                link2 = self.wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Notenübersicht")))
            except:
                 link2 = self.wait.until(EC.element_to_be_clickable((By.PARTIAL_LINK_TEXT, "Grades")))
        
        link2.click()
        
        # Wait for tree view to load (usually an info icon or specific text)
        try:
            self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "a[title='Leistungen anzeigen'], a[title='Show achievements']")))
            logger.info("Tree view loaded.")
        except:
            logger.warning("Timeout waiting for tree view icons, proceeding anyway.")
        
        # Target 3: Select degree program (if multiple)
        # Look for the info icon or the first valid link in the list of programs
        try:
            # The page is a tree view. We need to click the "Leistungen anzeigen" (Appears as an info icon usually)
            # for the specific degree program.
            # Try multiple times if needed, and verify we actually navigated
            
            # Find all potential links
            grade_links = []
            possible_selectors = [
                "a[title='Leistungen anzeigen']",
                "a[title='Show achievements']", 
                "a[title*='Notenspiegel']",
                "a[href*='notenspiegelStudent'] img[title='Leistungen anzeigen']",
            ]
            
            for selector in possible_selectors:
                elements = self.driver.find_elements(By.CSS_SELECTOR, selector)
                if elements:
                    grade_links.extend(elements)

            if grade_links:
                # Filter out duplicates if any (though elements are unique objects)
                logger.info(f"Found {len(grade_links)} potential 'Leistungen anzeigen' links.")
                
                # Logic: The last one is usually the most specific one in the tree
                # We will try clicking the last one, wait for table.
                # If table doesn't appear, go back (or re-find) and try others?
                # For now, let's just robustly click the last valid one.
                
                target_link = grade_links[-1]
                # Sometimes we need to click the direct parent A tag if we found an IMG
                if target_link.tag_name == 'img':
                    target_link = target_link.find_element(By.XPATH, "..")
                
                logger.info(f"Clicking link: {target_link.get_attribute('href')}")
                target_link.click()
                
                # WAIT for the table to appear to confirm navigation
                try:
                    # Wait for a table cell with "Prüfung" or "Exam" or "ECTS"
                    # Or just wait for ANY table that looks like a grade table
                    self.wait.until(lambda d: "Prüfung" in d.page_source or "Exam" in d.page_source or "ECTS" in d.page_source)
                    logger.info("Successfully navigated to grade table view.")
                except TimeoutException:
                    logger.warning("Clicked link but grade table did not appear within timeout.")
                    self._dump_debug_info("navigation_timeout")
                    
            else:
                 # Fallback to previous heuristic if no icon found
                 logger.warning("Specific grade link not found, trying generic asi link...")
                 try:
                      program_link = self.wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, "a[href*='asi']")))
                      program_link.click()
                      logger.info("Clicked generic degree program link.")
                      # Try to wait for table
                      self.wait.until(lambda d: "Prüfung" in d.page_source or "Exam" in d.page_source)
                 except:
                      logger.warning("Generic asi link also not found.")
        
        except Exception as e:
            logger.error(f"Navigation failed: {e}")
            self._dump_debug_info("navigation_failure")

        # Target 4: Locate HTML view (often an PDF icon vs HTML icon)
        # Usually BOSS shows the grades directly after selecting program, or asks for HTML vs PDF.
        # Assuming we might be there, or need one more click on "Info" equivalent.
        # Check if we have a table with 'Prüfung'
        if "Prüfung" not in self.driver.page_source and "Exam" not in self.driver.page_source:
             logger.warning("Grade table not immediately visible, checking for further links.")
        

    def _fetch_page_via_requests(self, url):
        """Fetch a page using httpx by reusing Selenium cookies."""
        logger.info(f"Fetching {url} via httpx...")
        
        # Extract cookies from Selenium
        selenium_cookies = self.driver.get_cookies()
        jar = httpx.Cookies()
        for cookie in selenium_cookies:
            jar.set(cookie['name'], cookie['value'], domain=cookie.get('domain', ''))
            
        user_agent = self.driver.execute_script("return navigator.userAgent")
        headers = {
            "User-Agent": user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1"
        }
        
        try:
            with httpx.Client(cookies=jar, headers=headers, timeout=20.0, follow_redirects=True) as client:
                response = client.get(url)
                response.raise_for_status()
                return response.text
        except Exception as e:
            logger.error(f"Failed to fetch via httpx: {e}")
            return None

    def get_data(self):
        try:
            self._setup_driver()
            self.login()
            self.navigate_to_grades()
            
            # Now that we are at the grades page, let's try to "turbo-charge" 
            # by fetching the final HTML content via httpx if we can determine the URL.
            current_url = self.driver.current_url
            logger.info(f"Final grade page URL: {current_url}")
            
            # Attempt to fetch via requests for faster processing (no JS overhead)
            html_content = self._fetch_page_via_requests(current_url)
            
            if html_content:
                logger.info("Successfully fetched HTML via hybrid httpx mode.")
                # We update the driver's page source (fake it or just parse it)
                # But since extract methods use soup, we can just pass content or parse it directly
                # For compatibility, we'll use a local soup object or just let the extract methods know.
                pass
            else:
                 logger.warning("Hybrid mode failed, falling back to Selenium source.")
                 html_content = self.driver.page_source

            # Extract degree identity
            soup = BeautifulSoup(html_content, 'html.parser')
            # Modification: extract methods now use the provided soup if needed, 
            # or we can just replace self.driver.page_source logic.
            # To keep it simple, I'll temporarily 'mock' the driver's page source or just edit the methods.
            
            # Let's slightly modify extract methods to accept optional html
            degree_identity = self.extract_degree_identity_from_content(html_content)
            exams, summary = self.extract_grades_from_content(html_content)
            
            if not exams:
                 logger.warning("No exams found! Dumping debug info.")
                 self._dump_debug_info("empty_exams")
            
            return {
                "timestamp": datetime.now().isoformat(),
                "degree_identity": degree_identity,
                "exams": exams,
                "summary": summary
            }
            
        except Exception as e:
            logger.error(f"Scraper failed: {e}")
            self._dump_debug_info("scraper_failure")
            return {"error": str(e)}
        finally:
            if self.driver:
                self.driver.quit()

    # Refactored Extraction Methods
    def extract_degree_identity_from_content(self, html_content):
        import re
        soup = BeautifulSoup(html_content, 'html.parser')
        degree_info = {'degree_type': None,'degree_subject': None,'po_version': None,'degree_code': None,'abschluss_code': None}
        try:
            # Strategy 1: Parse from table header cells (new BOSS format)
            header_cells = soup.find_all('th')
            for cell in header_cells:
                text = cell.get_text(strip=True)
                abschluss_match = re.search(r'Abschluss:\[(\d+)\]\s*([^S]+)', text, re.IGNORECASE)
                if abschluss_match:
                    degree_info['abschluss_code'] = abschluss_match.group(1)
                    type_text = abschluss_match.group(2).strip()
                    if 'Bachelor' in type_text: degree_info['degree_type'] = 'Bachelor'
                    elif 'Master' in type_text: degree_info['degree_type'] = 'Master'
                    else: degree_info['degree_type'] = type_text.split()[0] if type_text else None
                studiengang_match = re.search(r'Studiengang:\[([A-Z]\d+)\]\s*(.+?)(?:\(|$)', text, re.IGNORECASE)
                if studiengang_match:
                    degree_info['degree_code'] = studiengang_match.group(1)
                    degree_info['degree_subject'] = studiengang_match.group(2).strip()
            
            if not degree_info['degree_type']:
                abschluss_text_match = re.search(r'Abschluss\s+(\d+)\s+(Bachelor|Master)', html_content, re.IGNORECASE)
                if abschluss_text_match:
                    degree_info['abschluss_code'] = abschluss_text_match.group(1)
                    degree_info['degree_type'] = abschluss_text_match.group(2)
            
            if not degree_info['degree_subject']:
                font_elements = soup.find_all('font', class_='liste1')
                for font in font_elements:
                    text = font.get_text(strip=True)
                    po_match = re.search(r'(.+?)\s*\(PO-Version\s+(\d+)\)', text)
                    if po_match:
                        degree_info['degree_subject'] = po_match.group(1).strip()
                        degree_info['po_version'] = po_match.group(2)
                        break
        except: pass
        return degree_info

    def extract_grades_from_content(self, html_content):
        soup = BeautifulSoup(html_content, 'html.parser')
        tables = soup.find_all("table")
        target_table = None
        for table in tables:
            text = table.get_text()
            if "Prüfung" in text or "Exam" in text or "ECTS" in text:
                target_table = table
                break
        if not target_table: return [], {}
        rows = target_table.find_all("tr")
        exams = []
        total_ects = 0.0; grade_sum = 0.0; graded_count = 0
        header_map = {}
        data_rows = []
        for row in rows:
            th_list = row.find_all("th")
            if th_list:
                for idx, th in enumerate(th_list):
                    t = th.get_text(strip=True).lower()
                    if "nr" in t or ("id" in t and "ver" not in t): header_map['id'] = idx
                    elif "text" in t or "bezeichnung" in t: header_map['title'] = idx
                    elif "sem" in t: header_map['semester'] = idx
                    elif "note" in t or "grade" in t: header_map['grade'] = idx
                    elif "status" in t or "vermerk" in t: header_map['status'] = idx
                    elif "ects" in t or "credit" in t or "bonus" in t: header_map['credits'] = idx
                continue
            td_list = row.find_all("td")
            if not td_list or len(td_list) < 3: continue 
            data_rows.append(td_list)
        if not header_map: header_map = {'id': 0, 'title': 1, 'semester': 2, 'grade': 3, 'status': 4, 'credits': 5}
        for cells in data_rows:
            try:
                exam = {}
                idx = header_map.get('title')
                if idx is not None and idx < len(cells): exam['title'] = cells[idx].get_text(strip=True)
                idx = header_map.get('id')
                if idx is not None and idx < len(cells): exam['exam_id'] = cells[idx].get_text(strip=True)
                idx = header_map.get('semester')
                if idx is not None and idx < len(cells): exam['semester'] = cells[idx].get_text(strip=True)
                idx = header_map.get('grade')
                raw_grade = ""
                if idx is not None and idx < len(cells): raw_grade = cells[idx].get_text(strip=True).replace(',', '.')
                try:
                     exam['grade'] = float(raw_grade)
                     if exam['grade'] > 0:
                         grade_sum += exam['grade']
                         graded_count += 1
                except: exam['grade'] = None
                idx = header_map.get('status')
                if idx is not None and idx < len(cells): exam['status'] = cells[idx].get_text(strip=True)
                idx = header_map.get('credits')
                try:
                    if idx is not None and idx < len(cells):
                        c = float(cells[idx].get_text(strip=True).replace(',', '.'))
                        exam['credits'] = c
                        if exam.get('status') == "bestanden" or (exam['grade'] and exam['grade'] <= 4.0):
                             total_ects += c
                except: exam['credits'] = 0.0
                if exam.get('title'): exams.append(exam)
            except: continue
        official_gpa = 0.0; official_ects = 0.0
        if exams:
            last_exam = exams[-1]
            if last_exam.get('grade'): official_gpa = last_exam['grade']
            if last_exam.get('credits'): official_ects = last_exam['credits']
        final_gpa = official_gpa if official_gpa > 0 else (round(grade_sum / graded_count, 2) if graded_count > 0 else 0.0)
        final_ects = official_ects if official_ects > 0 else total_ects
        return exams, {"total_credits": final_ects, "current_gpa": final_gpa}
