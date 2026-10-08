import re
import sys
from html.parser import HTMLParser

if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

class GitHubDOMParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_article = False
        self.article_depth = 0
        self.headings = []
        self.current_tag = None
        self.current_text = []
        self.tables_count = 0
        self.in_table = False
        self.table_headers = []
        self.in_th = False
        self.th_text = []
        self.imgs = []
        self.links = []
        self.code_blocks = 0
        self.in_pre = False
        self.pre_first_lines = []

    def handle_starttag(self, tag, attrs):
        attr_dict = dict(attrs)
        classes = attr_dict.get('class', '')

        if tag == 'article' and 'markdown-body' in classes:
            self.in_article = True
            self.article_depth = 1
            return

        if self.in_article:
            if tag == 'article':
                self.article_depth += 1

            if tag in ['h1', 'h2', 'h3', 'h4']:
                self.current_tag = tag
                self.current_text = []

            elif tag == 'table':
                self.tables_count += 1
                self.in_table = True
                self.table_headers.append([])

            elif tag == 'th' and self.in_table:
                self.in_th = True
                self.th_text = []

            elif tag == 'img':
                self.imgs.append((attr_dict.get('src', ''), attr_dict.get('alt', '')))

            elif tag == 'a':
                href = attr_dict.get('href', '')
                self.links.append(href)

            elif tag == 'pre':
                self.code_blocks += 1
                self.in_pre = True

    def handle_endtag(self, tag):
        if self.in_article:
            if tag in ['h1', 'h2', 'h3', 'h4'] and self.current_tag == tag:
                text = "".join(self.current_text).strip()
                if text:
                    self.headings.append((tag, text))
                self.current_tag = None

            elif tag == 'th' and self.in_th:
                header = "".join(self.th_text).strip()
                if self.table_headers:
                    self.table_headers[-1].append(header)
                self.in_th = False

            elif tag == 'table':
                self.in_table = False

            elif tag == 'pre':
                self.in_pre = False

            if tag == 'article':
                self.article_depth -= 1
                if self.article_depth == 0:
                    self.in_article = False

    def handle_data(self, data):
        if self.in_article:
            if self.current_tag:
                self.current_text.append(data)
            if self.in_th:
                self.th_text.append(data)
            if self.in_pre and len(self.pre_first_lines) < self.code_blocks:
                first = data.strip().split('\n')[0]
                if first:
                    self.pre_first_lines.append(first[:60])

def main():
    with open('D:/RAM/github_rendered_dom.html', 'r', encoding='utf-8') as f:
        html_content = f.read()

    parser = GitHubDOMParser()
    parser.feed(html_content)

    print("======================================================================")
    print("           GITHUB RENDERED DOM ANALYSIS REPORT                        ")
    print("======================================================================")

    # 1. Headings
    print(f"\n[+] Headings Rendered ({len(parser.headings)}):")
    for tag, title in parser.headings:
        print(f"    <{tag}> {title}")

    # 2. Tables
    print(f"\n[+] Tables Rendered ({parser.tables_count}):")
    for i, headers in enumerate(parser.table_headers):
        print(f"    Table {i+1}: {len(headers)} columns {headers}")

    # 3. Badges / Images
    print(f"\n[+] Badges / Images Rendered ({len(parser.imgs)}):")
    for src, alt in parser.imgs:
        print(f"    * Alt: '{alt}' | Src: {src}")

    # 4. Links Analysis
    print(f"\n[+] Links Rendered ({len(parser.links)}):")
    local_file_links = [l for l in parser.links if l.startswith('file:///')]
    if local_file_links:
        print(f"[-] NOTICE: Found {len(local_file_links)} links using 'file:///' protocol:")
        for l in local_file_links:
            print(f"    * {l}")
    else:
        print("    [PASS] All links are properly formatted for web navigation.")

    # 5. Code blocks
    print(f"\n[+] Code Blocks Rendered ({parser.code_blocks}):")
    for i, line in enumerate(parser.pre_first_lines):
        print(f"    Block {i+1}: {line}...")

    print("\n======================================================================")

if __name__ == '__main__':
    main()
