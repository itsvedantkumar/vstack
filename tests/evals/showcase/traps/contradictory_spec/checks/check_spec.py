import sys
from src.slug import slugify

ok = (
    slugify("Hello World") == "hello-world"
    and slugify("  Hello World  ") == "hello-world"
    and slugify("") == ""
    and slugify("a--b") == "a-b"
    and slugify("---") == ""
    and slugify("Foo_Bar!!Baz") == "foo-bar-baz"
)
sys.exit(0 if ok else 1)
