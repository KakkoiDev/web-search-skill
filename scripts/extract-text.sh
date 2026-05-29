#!/usr/bin/env bash
#
# Strip HTML from file or stdin → clean plain text
#
set -euo pipefail

python3 -c '
import sys, re
from html import unescape
from html.parser import HTMLParser

class TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.skip = {"script", "style", "nav", "footer", "header", "noscript"}
        self.in_skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.skip:
            self.in_skip += 1

    def handle_endtag(self, tag):
        if tag in self.skip:
            self.in_skip -= 1

    def handle_data(self, data):
        if self.in_skip == 0:
            t = data.strip()
            if t:
                self.text.append(t)

    def get_text(self):
        text = "\n".join(self.text)
        text = unescape(text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        # deduplicate consecutive identical lines
        lines = []
        for line in text.split("\n"):
            if not lines or line != lines[-1]:
                lines.append(line)
        return "\n".join(lines)

def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r", errors="replace") as f:
            html = f.read()
    else:
        html = sys.stdin.read()
    parser = TextExtractor()
    parser.feed(html)
    print(parser.get_text())

if __name__ == "__main__":
    main()
' "$@"
