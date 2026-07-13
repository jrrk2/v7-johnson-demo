#!/usr/bin/env python3
# Test the uartstream diagnostic: phase1 listen (TX), phase2 inject+listen (RX).
import os,select,time,sys
os.system("stty -F /dev/ttyUSB2 115200 raw -echo")
fd=os.open("/dev/ttyUSB2",os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK); time.sleep(0.3)
def rd(dur):
    out=b""; t=time.time()
    while time.time()-t<dur:
        if select.select([fd],[],[],0.2)[0]:
            try: out+=os.read(fd,256)
            except BlockingIOError: pass
    return out
rd(1.0)                                 # time-bounded drain
got=rd(3)
print(f"TX stream (3s): {got[:40]!r} ({len(got)} bytes)")
for i in range(5): os.write(fd,b"x"); time.sleep(0.1)
got2=rd(3)
os.close(fd)
print(f"after 5 rx bytes: {got2[:40]!r}")
tx_ok=len(got)>10
last1=got[-1:] if got else b''
last2=got2[-1:] if got2 else b''
rx_ok=tx_ok and last2 and last1 and (last2!=last1)
print("RESULT: TX", "OK" if tx_ok else "FAIL",
      "| RX", "OK (payload advanced %r->%r)"%(last1,last2) if rx_ok else "FAIL (%r->%r)"%(last1,last2))
