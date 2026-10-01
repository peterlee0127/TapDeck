"""Build at the domain root and a subpath; catch broken assets and navigation."""

from html.parser import HTMLParser
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import unquote, urljoin, urlsplit


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.ids = set()
        self.links = []
        self.headings = 0
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate ID: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.headings += 1
        if tag == "img":
            assert "alt" in attrs, "Image missing alternative text"
        if tag == "html":
            assert attrs.get("lang") == "en", "Expected an English document"
        for name in ("href", "src"):
            if name in attrs:
                self.links.append(attrs[name])
        for candidate in attrs.get("srcset", "").split(","):
            if candidate.strip():
                self.links.append(candidate.split()[0])


site = Path(__file__).resolve().parent
for prefix in ("/", "/MacOS-clicker/"):
    base = f"https://preview.example{prefix}"
    with TemporaryDirectory(prefix="trackpad-site-") as directory:
        output = Path(directory)
        subprocess.run(
            ["hugo", "--source", str(site), "--destination", str(output),
             "--baseURL", base, "--minify", "--panicOnWarning", "--quiet"],
            check=True,
        )
        pages = {path: Page(path) for path in output.rglob("*.html")}
        assert output / "index.html" in pages, "Homepage was not generated"
        assert output / "404.html" in pages, "404 page was not generated"
        checked = 0
        for path, page in pages.items():
            assert page.headings == 1, f"Expected one H1 in {path.name}"
            page_url = urljoin(base, path.relative_to(output).as_posix())
            for link in page.links:
                url = urlsplit(urljoin(page_url, link))
                if url.netloc != "preview.example":
                    continue
                assert url.path.startswith(prefix), f"Escapes deployment path: {link}"
                target = output / unquote(url.path[len(prefix):])
                if target.is_dir():
                    target /= "index.html"
                assert target.is_file(), f"Missing asset or page: {link}"
                if url.fragment:
                    assert target in pages and unquote(url.fragment) in pages[target].ids, f"Missing anchor: {link}"
                checked += 1
        print(f"PASS {prefix}: {len(pages)} pages, {checked} internal references")
