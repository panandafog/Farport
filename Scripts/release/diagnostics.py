"""Credential-safe diagnostics for both Python stages and workflow startup failures."""
import os
import re


def sanitized(value):
    text = str(value)
    for key, secret in os.environ.items():
        if any(word in key for word in ("PASSWORD", "PRIVATE_KEY", "P12", "TOKEN", "CONTACT_PHONE", "DEMO_ACCOUNT", "BASE64")) and len(secret) > 3:
            text = text.replace(secret, "[REDACTED]")
    text = re.sub(r"-----BEGIN .*?PRIVATE KEY-----.*?-----END .*?PRIVATE KEY-----", "[REDACTED KEY]", text, flags=re.S)
    return re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[REDACTED JWT]", text)


def annotation(message, title, warning=False):
    if not os.environ.get("GITHUB_ACTIONS"):
        return

    def escape(value):
        return sanitized(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

    title = escape(title).replace(":", "%3A").replace(",", "%2C")
    print(f"::{'warning' if warning else 'error'} title={title}::{escape(message)}", flush=True)
