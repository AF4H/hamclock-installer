"""Wi-Fi defaults must have explicit ordering and preserve unrelated networks."""
import configparser
from io import StringIO
from pathlib import Path
import re
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
script = (ROOT/'scripts/configure-networks.sh').read_text()
program = re.search(r"<<'PRESETS'\n(.*?)\nPRESETS",script,re.S)[1]
wrapper = re.search(r"<<'COMITUP'\n(.*?)\nCOMITUP",script,re.S)[1]


class PresetTests(unittest.TestCase):
    def run_program(self, root, fail=False):
        def offline(command, **kwargs):
            settings=configparser.ConfigParser(interpolation=None)
            if kwargs.get('input'):
                settings.read_string(kwargs['input'])
                start=4
            else:
                settings.read_dict({'connection':{},'wifi':{}})
                start=4
            for key,value in zip(command[start::2],command[start+1::2]):
                section,_,name=key.partition('.')
                if key == 'ssid': section,name='wifi','ssid'
                elif key == 'con-name': section,name='connection','id'
                elif key == 'type': section,name='connection','type'
                elif section == 'wifi-sec': section='wifi-security'
                if not settings.has_section(section): settings.add_section(section)
                settings.set(section,name,value)
            if settings.get('wifi','ssid',fallback='') == '65;70;52;72;':
                settings['wifi']['ssid']='AF4H'
            stream=StringIO(); settings.write(stream)
            return SimpleNamespace(returncode=1 if fail else 0,stdout=stream.getvalue())
        with patch.object(sys,'argv',['-',str(root)]),patch('subprocess.run',offline):
            exec(compile(program,'presets','exec'),{'__name__':'__main__'})

    def test_existing_af4h_and_other_profiles_survive_repeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); folder=root/'etc/NetworkManager/system-connections'; folder.mkdir(parents=True)
            af4h=folder/'operator-af4h'
            af4h.write_text('[connection]\nid=Operator AF4H\nuuid=keep-me\n[wifi]\nssid=65;70;52;72;\n[wifi-security]\npsk=keep-this-key\n')
            other=folder/'other.nmconnection'; other.write_text('[wifi]\nssid=Other\n')
            self.run_program(root)
            settings=configparser.ConfigParser(); settings.read(af4h)
            self.assertEqual(settings['connection']['uuid'],'keep-me')
            self.assertEqual(settings['wifi-security']['psk'],'keep-this-key')
            self.assertEqual(settings['connection']['autoconnect-priority'],'100')
            fields=list(folder.glob('hamclock-preset-*.nmconnection')); self.assertEqual(len(fields),1)
            field=configparser.ConfigParser(); field.read(fields[0])
            self.assertEqual(field['wifi']['ssid'],'FieldLink')
            self.assertEqual(field['connection']['autoconnect-priority'],'50')
            self.assertEqual(field['wifi-security']['psk'],'h@mradio')
            self.assertEqual(fields[0].stat().st_mode & 0o777,0o600)
            original={p.name:p.read_bytes() for p in folder.glob('*')}
            self.run_program(root)
            self.assertEqual(original,{p.name:p.read_bytes() for p in folder.glob('*')})
            self.assertEqual(other.read_text(),'[wifi]\nssid=Other\n')

    def test_serialization_failure_leaves_profiles_intact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); folder=root/'etc/NetworkManager/system-connections'; folder.mkdir(parents=True)
            path=folder/'af4h.nmconnection'; path.write_text('[wifi]\nssid=AF4H\n')
            with self.assertRaises(SystemExit): self.run_program(root,fail=True)
            self.assertEqual(path.read_text(),'[wifi]\nssid=AF4H\n')
            self.assertEqual(len(list(folder.glob('*'))),1)

    def test_comitup_uses_priorities_and_stable_ties(self):
        module={'__name__':'test'}; exec(compile(wrapper,'wrapper','exec'),module)
        self.assertEqual(module['prioritize'](['FieldLink','Other','AF4H','Another'],{'AF4H':100,'FieldLink':50}),
                         ['AF4H','FieldLink','Other','Another'])
