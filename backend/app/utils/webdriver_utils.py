import os
import logging
from webdriver_manager.chrome import ChromeDriverManager

logger = logging.getLogger(__name__)

DEBUG_DIR = "/home/bilel0-0/uniapp/backend/chrome_debug_data"
_cached_driver_path = None

def get_cached_driver_path():
    global _cached_driver_path
    if _cached_driver_path is None:
        logger.info("Initializing ChromeDriver path...")
        try:
            driver_path = ChromeDriverManager().install()
            # Fix for WDM behavior where it returns THIRD_PARTY_NOTICES
            if "THIRD_PARTY_NOTICES" in driver_path:
                driver_dir = os.path.dirname(driver_path)
                driver_path = os.path.join(driver_dir, "chromedriver")
                try: os.chmod(driver_path, 0o755)
                except: pass
            _cached_driver_path = driver_path
        except Exception as e:
            logger.error(f"Failed to install/find ChromeDriver: {e}")
            raise
    return _cached_driver_path
