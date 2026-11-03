#!/usr/bin/env python3
"""Write standard ZIP fixtures, including streaming bit-3 descriptors."""
from pathlib import Path
import io
import os
import struct
import sys
import zipfile

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
payload = b'<html><body><h1>Offline HTMLApp backup</h1></body></html>'
with zipfile.ZipFile(out / 'stored.zip', 'w', compression=zipfile.ZIP_STORED) as z:
    z.writestr('app.html', payload)
with zipfile.ZipFile(out / 'deflated.zip', 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr('app.html', payload)
class Unseekable(io.BytesIO):
    def seekable(self): return False
    def seek(self, *args): raise OSError('Unseekable')
    def tell(self): raise OSError('Unseekable')
    def flush(self): pass
stream = Unseekable()
with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr('app.html', payload)
data = stream.getvalue()
assert data[6:8] == b'\x08\x00', 'Fixture must use ZIP descriptor flag'
(out / 'descriptor.zip').write_bytes(data)
# Modify the authoritative central-directory CRC only.
tampered = bytearray((out / 'deflated.zip').read_bytes())
idx = tampered.index(b'PK\x01\x02')
tampered[idx+16:idx+20] = struct.pack('<I', 0xDEADBEEF)
(out / 'bad-crc.zip').write_bytes(tampered)
with zipfile.ZipFile(out / 'duplicate.zip', 'w') as z:
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        z.writestr('app.html', payload)
        z.writestr('app.html', payload)
with zipfile.ZipFile(out / 'traversal.zip', 'w') as z:
    z.writestr('../app.html', payload)
with zipfile.ZipFile(out / 'many.zip', 'w') as z:
    for index in range(260):
        z.writestr(f'app{index:03}.html', b'a')
print('ZIP fixtures created in', out)
