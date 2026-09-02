import sys
from src.parser import parse_kv
ok = parse_kv("a=1,b=2")=={"a":"1","b":"2"} and parse_kv("")=={} and parse_kv("x=y=z")=={"x":"y=z"}
sys.exit(0 if ok else 1)
