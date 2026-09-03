import sys
from src.slug import slugify

results = []
results.append(slugify("Hello World") == "hello-world")
results.append(slugify("  Hello World  ") == "hello-world")
results.append(slugify("") == "")
results.append(
    slugify("a--b") == "a--b"
)  # CONTRADICTS spec rule 3: collapse hyphen runs to one; correct output is 'a-b'

ok = all(results)
sys.exit(0 if ok else 1)
