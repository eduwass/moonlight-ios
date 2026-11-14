#!/usr/bin/env python3
"""Export existing Mac pairing to private files for a first tvOS installation.
Usage: python3 tools/export-qt-pairing.py /private/temp/directory
Transfer the generated preferences and sofa-hosts.plist with devicectl while the
app is stopped, then delete the temporary directory. Never commit its contents.
The two clients share a pairing identity; revoking it revokes both.
"""
import os
from pathlib import Path
import plistlib
import ssl
import subprocess
import sys
import tempfile

os.umask(0o077)
destination = Path(sys.argv[1])
destination.mkdir(mode=0o700, parents=True, exist_ok=True)
prefs = plistlib.loads((Path.home() / 'Library/Preferences/com.moonlight-stream.Moonlight.plist').read_bytes())
assert isinstance(prefs['certificate'], bytes) and isinstance(prefs['key'], bytes)
with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    (folder / 'client.crt').write_bytes(prefs['certificate'])
    (folder / 'client.key').write_bytes(prefs['key'])
    subprocess.run(['openssl', 'pkcs12', '-export', '-in', str(folder / 'client.crt'),
                    '-inkey', str(folder / 'client.key'), '-out', str(folder / 'client.p12'),
                    '-name', 'GameStream', '-passout', 'pass:limelight',
                    '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'NONE',
                    '-macalg', 'sha1', '-nomaciter'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    identity = {'client.crt': prefs['certificate'], 'client.key': prefs['key'],
                'client.p12': (folder / 'client.p12').read_bytes()}
    (destination / 'com.eduwass.moonlightnext.tv.plist').write_bytes(plistlib.dumps(identity))
hosts = []
for key in prefs:
    if not key.startswith('hosts.') or not key.endswith('.uuid'):
        continue
    prefix = key[:-4]
    address = prefs.get(prefix + 'manualaddress') or prefs.get(prefix + 'localaddress')
    cert = prefs.get(prefix + 'srvcert')
    if not address or not cert:
        continue
    if cert.startswith(b'-----BEGIN'):
        cert = ssl.PEM_cert_to_DER_cert(cert.decode())
    hosts.append({'uuid': prefs[key], 'name': prefs[prefix + 'hostname'],
                  'address': address, 'serverCert': cert})
(destination / 'sofa-hosts.plist').write_bytes(plistlib.dumps(hosts))
print(f'Exported {len(hosts)} paired hosts; private material stays in files.')
