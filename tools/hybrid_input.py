"""Apply a private, original-instruction-verified camera compatibility profile."""
import json,re,struct
def normalize(text,exe=None):
    records=json.loads(text)
    if not isinstance(records,list) or len(records)>16:raise ValueError('At most sixteen hybrid call sites')
    profile={}
    for row in records:
        if set(row)!={'site','callee'}:raise ValueError('Hybrid profile requires site/callee')
        site,callee=(int(row[k],0) if isinstance(row[k],str) else row[k] for k in ['site','callee'])
        if not 0<site<2**32 or not 0<callee<2**32 or site in profile:raise ValueError('Invalid hybrid call site')
        profile[site]=callee
    if profile and exe:
        data=exe.read_bytes();pe=struct.unpack_from('<I',data,0x3c)[0];count=struct.unpack_from('<H',data,pe+6)[0]
        optional=struct.unpack_from('<H',data,pe+20)[0];base=struct.unpack_from('<I',data,pe+24+28)[0]
        sections=pe+24+optional
        for site,callee in profile.items():
            found=False
            for i in range(count):
                virtual_size,rva,size,raw=struct.unpack_from('<IIII',data,sections+40*i+8)
                if rva<=site-base<rva+min(virtual_size,size):
                    pos=raw+site-base-rva;found=data[pos]==0xe8 and site+5+struct.unpack_from('<i',data,pos+1)[0]==callee;break
            if not found:raise ValueError(f'Original x86 CALL identity mismatch at {site:#x}')
    return profile
def instrument(content,profile):
    matched=set();site=0
    def replace(match):
        nonlocal site
        if match.group(1):site=int(match.group(1),16);return match.group(0)
        callee=int(match.group(2),16)
        if site not in profile:return match.group(0)
        if callee!=profile[site] or site in matched:raise ValueError('Ambiguous camera call in generated code')
        matched.add(site)
        return match.group(0)+f'fnv_input_mouse_camera(c,0x{site:x}u);'.encode()
    result=re.sub(rb'L_([0-9a-f]+):|g_([0-9a-f]+)\(c\);',replace,content)
    if matched:result=result.replace(b'#include "rt.h"',b'#include "rt.h"\nvoid fnv_input_mouse_camera(CPU *,uint32_t);',1)
    return result,matched
