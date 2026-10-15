# -*- coding: utf-8 -*-
"""What scripts/build-site, build-manual and build-privacy have in common.

One list of languages, in the order every language switcher shows them, and
one set of page names, so the three generators can't drift apart: the manual's
switcher once listed the languages in a different order from the landing
pages' because each script carried its own copy.

Imported as a module (the scripts directory is on sys.path when any of them
runs), stdlib only.
"""

SITE = "https://pockterm.com"
APP_STORE = "https://apps.apple.com/app/id6789968094"
SOURCE = "https://github.com/jhancock1975/pockterm"

# (code, endonym, direction) — the order the language switchers show them in.
LANGS = [
    ("en", "English", "ltr"),
    ("es", "Español", "ltr"),
    ("fr", "Français", "ltr"),
    ("it", "Italiano", "ltr"),
    ("el", "Ελληνικά", "ltr"),
    ("ru", "Русский", "ltr"),
    ("uk", "Українська", "ltr"),
    ("ar", "العربية", "rtl"),
    ("he", "עברית", "rtl"),
    ("hi", "हिन्दी", "ltr"),
    ("te", "తెలుగు", "ltr"),
    ("ja", "日本語", "ltr"),
    ("ko", "한국어", "ltr"),
    ("zh-Hans", "简体中文", "ltr"),
    ("zh-Hant", "繁體中文", "ltr"),
]
ORDER = [code for code, _, _ in LANGS]
RTL = {code for code, _, direction in LANGS if direction == "rtl"}


# Site-relative paths. Flat files, because CloudFront applies its default root
# object only at the root, so a directory URL 404s against the S3 origin.
def home(code):
    return "/" if code == "en" else f"/{code}.html"


def manual(code):
    return "/manual.html" if code == "en" else f"/manual-{code}.html"


def privacy(code):
    # English keeps /privacy.html: it is the Privacy Policy URL App Store
    # Connect has on file.
    return "/privacy.html" if code == "en" else f"/privacy-{code}.html"


def html_attrs(code):
    """The lang and dir attributes for a page's <html> tag."""
    return f'lang="{code}"' + (' dir="rtl"' if code in RTL else "")


def alternates(path_for, default="en"):
    """hreflang <link> tags for every language plus x-default, as a list."""
    tags = [f'<link rel="alternate" hreflang="{code}" href="{SITE}{path_for(code)}">'
            for code in ORDER]
    tags.append(f'<link rel="alternate" hreflang="x-default" '
                f'href="{SITE}{path_for(default)}">')
    return tags


def langbar(current, label, path_for):
    """The language row: current language as text, the others as links."""
    items = [f'<span class="lb-label">{label}</span>']
    for code, name, _ in LANGS:
        if code == current:
            items.append(f'<span aria-current="true" lang="{code}">{name}</span>')
        else:
            items.append(f'<a href="{path_for(code)}" lang="{code}" '
                         f'hreflang="{code}">{name}</a>')
    return f'<nav class="langbar" aria-label="{label}">' + "".join(items) + "</nav>"
