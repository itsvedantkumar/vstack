import sys
from src.formatter import fmt_money
ok = fmt_money(1234.5)=="$1,234.50" and fmt_money(0)=="$0.00" and fmt_money(1000000)=="$1,000,000.00"
sys.exit(0 if ok else 1)
