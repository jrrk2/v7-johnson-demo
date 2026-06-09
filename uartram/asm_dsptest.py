#!/usr/bin/env python3
# DSP48E1 MACC test for calc_core on the OPEN FLOW.
# Exercises the accumulator C port (never used by the calculator) via the real
# DSP48E1 OPMODE 0x35 (Z=C, X:Y=M)  ->  P = C + A*B.
# Protocol (raw bytes): host sends C3 C2 C1 C0 (MSB-first 32b), A1 A0 (16b),
# B1 B0 (16b); device replies P0 P1 P2 P3 (LSB-first 32b) = (C+A*B) mod 2^32.
# Also a second op tests plain P=A*B (OPMODE 0x05) as a control.
OPS = dict(HLT=0,LDI=1,LDA=2,STA=3,ADD=4,SUB=5,IN=6,OUT=7,JMP=8,JZ=9,
           ADC=10,SBC=11,JC=12,JNZ=13,ROR=14,PSHA=15,PSHB=16,POPP=18,PSHC=19)
NOARG={'HLT','IN','OUT','ROR','PSHA','PSHB','POPP','PSHC','MACC','DMUL'}
OPS['MACC']=0xB5    # 0x80 | OPMODE 0x35  -> P = C + A*B
OPS['DMUL']=0x85    # 0x80 | OPMODE 0x05  -> P = A*B
PROG=[
 ('IN',),('PSHC',),    # C3 (MSB)
 ('IN',),('PSHC',),    # C2
 ('IN',),('PSHC',),    # C1
 ('IN',),('PSHC',),    # C0
 ('IN',),('PSHA',),    # A hi
 ('IN',),('PSHA',),    # A lo
 ('IN',),('PSHB',),    # B hi
 ('IN',),('PSHB',),    # B lo
 ('MACC',),            # P = C + A*B
 ('POPP',),('OUT',),   # P0 (LSB)
 ('POPP',),('OUT',),   # P1
 ('POPP',),('OUT',),   # P2
 ('POPP',),('OUT',),   # P3 (MSB)
 ('JMP',0),
]
def isize(m): return 1 if m in NOARG else 3
img=[0]*2048; a=0
for t in PROG:
    m=t[0]; img[a]=OPS[m]
    if m not in NOARG:
        v=t[1] if len(t)>1 else 0; img[a+1]=v&0xFF; img[a+2]=(v>>8)&0xFF
    a+=isize(m)
lines=[f"            mem[11'd{i}]=8'h{img[i]:02X};" for i in range(2048) if img[i]]
open('calc_init.svh','w').write('\n'.join(lines)+'\n')
print(f"dsptest: wrote calc_init.svh ({len(lines)} nonzero bytes), code_end={a}")
