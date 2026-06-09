#!/usr/bin/env python3
# 16-bit ADC/SBC isolation for calc_core (open-flow inter-byte carry debug).
# Protocol: host sends Alo,Ahi,Blo,Bhi; device replies:
#   [sub_lo][sub_hi]  (16-bit A-B via SUB then SBC)
#   [add_lo][add_hi]  (16-bit A+B via ADD then ADC)
# Isolates OP_ADC/OP_SBC (carry-in from the cy register) vs the working
# single-byte OP_ADD/OP_SUB.
OPS = dict(HLT=0,LDI=1,LDA=2,STA=3,ADD=4,SUB=5,IN=6,OUT=7,JMP=8,JZ=9,
           ADC=10,SBC=11,JC=12,JNZ=13,ROR=14)
NOARG = {'HLT','IN','OUT','ROR'}
AL=0x200; AH=0x201; BL=0x202; BH=0x203; RL=0x204; RH=0x205
PROG = [
 ('IN',None),('STA',AL),
 ('IN',None),('STA',AH),
 ('IN',None),('STA',BL),
 ('IN',None),('STA',BH),
 # ---- 16-bit SUB: A - B ----
 ('LDA',AL),('SUB',BL),('STA',RL),
 ('LDA',AH),('SBC',BH),('STA',RH),
 ('LDA',RL),('OUT',None),
 ('LDA',RH),('OUT',None),
 # ---- 16-bit ADD: A + B ----
 ('LDA',AL),('ADD',BL),('STA',RL),
 ('LDA',AH),('ADC',BH),('STA',RH),
 ('LDA',RL),('OUT',None),
 ('LDA',RH),('OUT',None),
 ('JMP',0),
]
def isize(m): return 1 if m in NOARG else 3
img=[0]*2048; addr=0
for mne,arg in PROG:
    img[addr]=OPS[mne]
    if mne not in NOARG:
        v=arg or 0; img[addr+1]=v&0xFF; img[addr+2]=(v>>8)&0xFF
    addr+=isize(mne)
lines=[f"            mem[11'd{a}]=8'h{img[a]:02X};" for a in range(2048) if img[a]]
open('calc_init.svh','w').write('\n'.join(lines)+'\n')
print(f"subtest16: wrote calc_init.svh ({len(lines)} nonzero bytes), code_end={addr}")
