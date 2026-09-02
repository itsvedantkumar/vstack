import sys
from solution import average
cases=[([1,2],1.5),([2,2,5],3.0),([10],10.0),([1,2,3,4],2.5),([0,0],0.0)]
bad=0
for inp,want in cases:
    got=average(list(inp))
    if abs(got-want)>1e-9:
        print(f"FAIL average({inp})={got} want {want}"); bad+=1
sys.exit(1 if bad else 0)
