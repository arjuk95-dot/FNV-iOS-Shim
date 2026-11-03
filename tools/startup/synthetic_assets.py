"""Author-created XML and one-file BSA fixtures, containing no original assets."""
import struct
import zlib

XML=b'<rect name="Strings"><_background_fill_alpha>32</_background_fill_alpha><_Has360Controller>0</_Has360Controller></rect>\n'

def name_hash(stem,extension=''):
    """TES4-family archive name hash, for lowercase ASCII fixture names."""
    data=stem.lower().replace('/','\\').encode('ascii');length=len(data)
    if not length:return 0
    low=(data[0]<<24)|(length<<16)|data[-1]
    if length>=3:low|=data[-2]<<8
    def rolling(sequence):
        value=0
        for byte in sequence:value=(value*65599+byte)&0xffffffff
        return value
    upper=rolling(data[1:-2]) if length>=4 else 0
    upper=(upper+rolling(extension.lower().encode('ascii')))&0xffffffff
    return (upper<<32)|low

def prepare(directory,packed=False,compressed=True):
    data=directory/'Data';data.mkdir()
    if packed:
        folder=b'menus\0';name=b'globals.xml\0'
        payload=struct.pack('<I',len(XML))+zlib.compress(XML) if compressed else XML
        folder_block=36+16
        file_data=folder_block+1+len(folder)+16+len(name)
        header=struct.pack('<4s8I',b'BSA\0',104,36,7 if compressed else 3,1,1,len(folder),len(name),0x100)
        folder_record=struct.pack('<QII',name_hash('menus'),1,folder_block+len(name))
        file_record=struct.pack('<QII',name_hash('globals','.xml'),len(payload),file_data)
        archive=header+folder_record+bytes([len(folder)])+folder+file_record+name+payload
        assert len(archive)==file_data+len(payload)
        (data/'Fallout - Misc.bsa').write_bytes(archive)
    else:
        (data/'Menus').mkdir();(data/'Menus/globals.xml').write_bytes(XML)
    (directory/'Fallout_default.ini').write_text('[Archive]\nbUseArchives=1\nSArchiveList='+('Fallout - Misc.bsa' if packed else '')+'\n')
