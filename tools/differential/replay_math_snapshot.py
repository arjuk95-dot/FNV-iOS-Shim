#!/usr/bin/env python3
"""Compare a repaired CRT dispatcher with original x86 from a captured guest frame.

Each side receives identical original PE data, captured stack/frame/TEB and GPRs.
The actual captured ST0 plus derived IEEE input classes are tested. Initial PE
globals are used on both sides; this is a controlled fixture, not a full game replay.
All value/flag/memory differences are retained in the report.
"""
import argparse
import ctypes
import json
import math
from pathlib import Path
import struct
from difftest import Worker,GPRS,UC_GPR,FLAGS,IMAGE_BASE,f80_to_float,load_pe
from unicorn import UC_HOOK_CODE,UC_HOOK_MEM_WRITE,UcError
from unicorn.x86_const import *

def f80(value):
    sign=0x8000 if math.copysign(1.0,value)<0 else 0
    if math.isnan(value):return (0xc000000000000000,sign|0x7fff)
    if math.isinf(value):return (0x8000000000000000,sign|0x7fff)
    if value==0:return (0,sign)
    mantissa,exponent=math.frexp(abs(value))
    return (int(math.ldexp(mantissa,64)),sign|(exponent+16382))

def same(a,b):
    if math.isnan(a) and math.isnan(b):return True
    return a==b and (a!=0 or math.copysign(1,a)==math.copysign(1,b))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exe');parser.add_argument('library');parser.add_argument('snapshot',type=Path)
    parser.add_argument('--registers',type=Path,default=Path(__file__).with_name('ghidra-x86-registers.json'))
    parser.add_argument('--entry',type=lambda s:int(s,0))
    parser.add_argument('--targets',default='')
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    image,_=load_pe(args.exe)
    if args.snapshot.is_dir():
        candidates=[]
        for path in sorted(args.snapshot.glob('fallback-*-state.json')):
            data=json.loads(path.read_text());offset=data['gpr'][2]-IMAGE_BASE
            if offset<0 or offset+32>len(image):continue
            operation_targets=struct.unpack_from('<4I',image,offset+16)
            if data['root'] in operation_targets:candidates.append(path)
        if not candidates:raise ValueError('No captured operation-record context in snapshot directory')
        args.snapshot=candidates[0]
    metadata=json.loads(args.snapshot.read_text())
    if args.entry is None:args.entry=metadata['source_entry']
    prefix=args.snapshot.name.removesuffix('-state.json')
    cpu=(args.snapshot.parent/(prefix+'-cpu.bin')).read_bytes()
    captured=struct.unpack_from('<d',cpu,4352)[0]
    cases=[('captured',captured),('zero',0.0),('negative_zero',-0.0),('one',1.0),('negative_one',-1.0),
           ('ten',10.0),('negative_ten',-10.0),('positive_infinity',math.inf),('negative_infinity',-math.inf),('quiet_nan',math.nan)]
    targets={int(value,0) for value in args.targets.split(',')} if args.targets else set(struct.unpack_from('<4I',image,metadata['gpr'][2]-IMAGE_BASE+16))
    registers=json.loads(args.registers.read_text())
    results=[]
    for name,value in cases:
        worker=Worker(args.exe,args.library,registers);mu=worker.mu
        ctypes.memmove(ctypes.addressof(worker.cpu),cpu,len(cpu))
        mapped={address for lo,hi,_ in mu.mem_regions() for address in range(lo,hi+1,4096)}
        regions={}
        for kind in ['stack','frame','teb']:
            base=metadata[kind+'_base'];data=(args.snapshot.parent/(prefix+'-'+kind+'.bin')).read_bytes()
            for page in range(base,base+len(data),4096):
                if page not in mapped:mu.mem_map(page,4096);mapped.add(page)
            worker.poke(base,data);regions[base]=len(data)
        # Rebuild flat 32-bit segmentation, with FS referring to the captured TEB.
        teb=metadata['teb_base'];gdt=teb+0x1f00
        def desc(base,limit,access,flags):
            return struct.pack('<HHBBBB',limit&0xffff,base&0xffff,(base>>16)&255,access,
                               ((limit>>16)&15)|(flags<<4),(base>>24)&255)
        table=b'\0'*8+desc(0,0xfffff,0x9b,0xc)+desc(0,0xfffff,0x93,0xc)+desc(teb,0xfff,0x93,4)
        worker.poke(gdt,table)
        mu.reg_write(UC_X86_REG_GDTR,(0,gdt,len(table)-1,0));mu.reg_write(UC_X86_REG_CS,8)
        for segment in [UC_X86_REG_SS,UC_X86_REG_DS,UC_X86_REG_ES]:mu.reg_write(segment,16)
        mu.reg_write(UC_X86_REG_FS,24)
        for i,reg in enumerate(GPRS):mu.reg_write(UC_GPR[reg],struct.unpack_from('<I',cpu,4*i)[0])
        flags=2
        for reg,bit in FLAGS.items():flags|=(worker.getreg(reg,1)&1)<<bit
        flags|=(cpu[522]&1)<<10
        mu.reg_write(UC_X86_REG_EFLAGS,flags)
        top=cpu[8900]&7
        struct.pack_into('<d',worker.cpu,4352,value)
        for i in range(8):
            number=value if i==0 else struct.unpack_from('<d',cpu,4352+16*i)[0]
            mu.reg_write(UC_X86_REG_FP0+((top+i)&7),f80(number))
        sw=(top<<11)|((cpu[4240]&1)<<8)|((cpu[4241]&1)<<9)|((cpu[4242]&1)<<10)|((cpu[4243]&1)<<14)
        mu.reg_write(UC_X86_REG_FPSW,sw);mu.reg_write(UC_X86_REG_FPTAG,0)
        mu.reg_write(UC_X86_REG_FPCW,struct.unpack_from('<H',cpu,4256)[0]);mu.reg_write(UC_X86_REG_MXCSR,0x1f80)
        for i in range(8):mu.reg_write(UC_X86_REG_XMM0+i,int.from_bytes(cpu[4608+64*i:4624+64*i],'little'))
        visited=set();writes=[]
        mu.hook_add(UC_HOOK_CODE,lambda u,a,s,d:visited.add(a))
        mu.hook_add(UC_HOOK_MEM_WRITE,lambda u,t,a,s,v,d:writes.append((a,s)))
        return_pc=metadata['return_pc']
        row=dict(case=name,input=repr(value),entry=hex(args.entry))
        try:mu.emu_start(args.entry,return_pc,count=200000)
        except UcError as error:
            row.update(verdict='invalid_x86_fixture',detail=str(error),pc=hex(mu.reg_read(UC_X86_REG_EIP)))
            results.append(row);continue
        if mu.reg_read(UC_X86_REG_EIP)!=return_pc:
            row.update(verdict='invalid_x86_fixture',detail='reference budget exhausted');results.append(row);continue
        native=worker.lib.rt_run(worker.index[args.entry],ctypes.addressof(worker.cpu),200000)
        gpr_diffs={reg:[worker.getreg(reg),mu.reg_read(UC_GPR[reg])] for reg in GPRS if worker.getreg(reg)!=mu.reg_read(UC_GPR[reg])}
        expected_top=(mu.reg_read(UC_X86_REG_FPSW)>>11)&7
        expected=f80_to_float(*mu.reg_read(UC_X86_REG_FP0+expected_top))
        actual=struct.unpack_from('<d',worker.cpu,4352)[0]
        flag_diffs={reg:[worker.getreg(reg,1),(mu.reg_read(UC_X86_REG_EFLAGS)>>bit)&1]
                    for reg,bit in FLAGS.items() if worker.getreg(reg,1)!=((mu.reg_read(UC_X86_REG_EFLAGS)>>bit)&1)}
        memory=[]
        for address,size in writes:
            a=ctypes.string_at(worker.mem+address,size);b=bytes(mu.mem_read(address,size))
            if a!=b and len(memory)<20:memory.append(dict(address=hex(address),native=a.hex(),x86=b.hex()))
        observable_match=not native and not gpr_diffs and worker.cpu[8900]==expected_top and same(actual,expected)
        row.update(verdict='observable_match' if observable_match else 'mismatch',native_trap=native,
                   native_result=repr(actual),x86_result=repr(expected),gpr_differences=gpr_diffs,
                   native_top=worker.cpu[8900],x86_top=expected_top,flag_differences=flag_diffs,
                   written_memory_differences=memory,reference_targets=[hex(t) for t in sorted(targets&visited)])
        results.append(row)
    report=dict(kind='snapshot_based_controlled_fixture',initial_image_globals=True,
                original_runtime_snapshot=str(args.snapshot.name),results=results,
                entry_count_is_not_correctness_evidence=True)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
    if any(r['verdict']=='mismatch' for r in results) or not any(r['verdict']=='observable_match' for r in results):raise SystemExit(1)

if __name__=='__main__':main()
