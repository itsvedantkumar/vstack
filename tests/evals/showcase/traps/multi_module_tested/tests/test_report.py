import sys, subprocess
r = subprocess.run(["bash","lib/report.sh","1","2","3"],capture_output=True,text=True)
sys.exit(0 if r.stdout.strip()=="total: 6" else 1)
