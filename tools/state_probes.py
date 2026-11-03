"""Validate small numeric probe specifications and instrument selected entry markers."""
import json
import re

def normalize(text):
    records=json.loads(text)
    if not isinstance(records,list) or len(records)>16:raise ValueError('At most 16 entry probes')
    probes={}
    for record in records:
        if not isinstance(record,dict) or set(record)!={'entry','offsets'}:raise ValueError('Entry and offsets required')
        entry=int(record['entry'],0) if isinstance(record['entry'],str) else record['entry']
        offsets=[int(v,0) if isinstance(v,str) else v for v in record['offsets']]
        if type(entry)!=int or not 0<entry<2**32 or entry in probes:raise ValueError('Invalid or repeated guest entry')
        if not 1<=len(offsets)<=16 or any(type(v)!=int or not 0<=v<=4096 for v in offsets):raise ValueError('Invalid field offsets')
        probes[entry]=offsets
    return probes

def instrument(content,probes):
    matched=set()
    def replace(match):
        entry=int(match.group(1),16)
        if entry not in probes:return match.group(0)
        matched.add(entry)
        offsets=','.join(hex(v)+'u' for v in probes[entry])
        return match.group(0)+f'rt_diag_watch(c,0x{entry:x}u,(const uint32_t[]){{{offsets}}},{len(probes[entry])});'.encode()
    output=re.sub(rb'RT_ENTER\(0x([0-9a-f]+)u\);',replace,content)
    if matched:output=output.replace(b'#include "rt.h"',b'#include "rt.h"\nvoid rt_diag_watch(CPU *,uint32_t,const uint32_t *,unsigned);',1)
    return output,matched
