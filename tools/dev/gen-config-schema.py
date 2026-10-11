"""D01: the schema of ii's config.json, read from the staged Config.qml (so it includes ii-windows'
own options) and from the settings pages (the bounds their spin boxes already enforce).

    python gen-config-schema.py --stage <staged ii dir>          write shared/config-schema.json and
                                                                 host/src/config_schema.inc
    python gen-config-schema.py --stage <staged ii dir> --check  fail if either file is out of date

What is derived, and nothing else:
  - every `property <type> name: default` of the JsonAdapter, with its dotted path and JSON kind
    (bool / int / real / string / list / list of strings / any / object);
  - an enumeration when the line's comment lists values as `0: A | 1: B`;
  - a numeric range when a ConfigSpinBox in the settings reads that option (`from:` / `to:`).
Unknown keys in a user's file are never an error: only a key that exists and has the wrong kind, an
integer outside its enumeration, or a number outside the range the settings page itself allows.
"""
import argparse
import json
import os
import re
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT_JSON = os.path.join(REPO, 'shared', 'config-schema.json')
OUT_INC = os.path.join(REPO, 'host', 'src', 'config_schema.inc')

KIND = {'bool': 'bool', 'int': 'int', 'real': 'real', 'double': 'real', 'string': 'string', 'color': 'string',
        'url': 'string', 'var': 'any', 'list<string>': 'strings', 'list<int>': 'list', 'list<real>': 'list',
        'list<var>': 'list', 'list<bool>': 'list', 'list<color>': 'strings', 'list<url>': 'strings'}


def strip_strings(line):
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', re.sub(r"'(?:\\.|[^'\\])*'", "''", line))


def code_of(line):
    """The line without strings and without the // comment."""
    stripped = strip_strings(line)
    cut = stripped.find('//')
    return stripped if cut < 0 else stripped[:cut]


def parse_config(path):
    text = open(path, encoding='utf-8').read().splitlines()
    start = next(i for i, l in enumerate(text) if re.search(r'JsonAdapter\s*\{', l))
    keys = {}
    objects = []
    stack = []   # names of the JsonObjects we are inside
    nest = 0     # unbalanced [ / { of a multi-line value (a list or object literal)
    for line in text[start + 1:]:
        code = code_of(line)
        if nest > 0:
            nest += code.count('[') + code.count('{') - code.count(']') - code.count('}')
            continue
        m = re.match(r'\s*property\s+JsonObject\s+(\w+)\s*:\s*JsonObject\s*\{\s*$', code)
        if m:
            stack.append(m.group(1))
            objects.append('.'.join(stack))
            continue
        m = re.match(r'\s*property\s+([\w<>]+)\s+(\w+)\s*:(.*)$', code)
        if m:
            kind = KIND.get(m.group(1))
            if kind is None:
                raise SystemExit(f'gen-config-schema: unknown property type {m.group(1)} at {".".join(stack + [m.group(2)])}')
            dotted = '.'.join(stack + [m.group(2)])
            entry = {'kind': kind}
            comment = line[line.find('//') + 2:] if '//' in strip_strings(line) else ''
            values = re.findall(r'(?:^|\|)\s*(-?\d+)\s*:', comment)
            if kind == 'int' and len(values) >= 2:
                entry['enum'] = [int(v) for v in values]
            keys[dotted] = entry
            rest = m.group(3)
            nest = rest.count('[') + rest.count('{') - rest.count(']') - rest.count('}')
            continue
        if code.strip() == '}':
            if not stack:
                break  # the adapter closed
            stack.pop()
    return keys, objects


def parse_ranges(settings_dir):
    ranges = {}
    if not os.path.isdir(settings_dir):
        return ranges
    for name in sorted(os.listdir(settings_dir)):
        if not name.endswith('.qml'):
            continue
        text = open(os.path.join(settings_dir, name), encoding='utf-8').read()
        for block in re.finditer(r'ConfigSpinBox\s*\{(.*?)\n\s*\}', text, re.S):
            body = block.group(1)
            value = re.search(r'value:\s*Config\.options\.([\w.]+)\s*$', body, re.M)
            low = re.search(r'\bfrom:\s*(-?\d+(?:\.\d+)?)', body)
            high = re.search(r'\bto:\s*(-?\d+(?:\.\d+)?)', body)
            if value and low and high:
                ranges[value.group(1)] = [float(low.group(1)), float(high.group(1))]
    return ranges


def build(stage):
    keys, objects = parse_config(os.path.join(stage, 'modules', 'common', 'Config.qml'))
    for path, (low, high) in parse_ranges(os.path.join(stage, 'modules', 'settings')).items():
        if path in keys and keys[path]['kind'] in ('int', 'real'):
            keys[path]['range'] = [int(low) if low == int(low) else low, int(high) if high == int(high) else high]
    return {'schema': 1, 'objects': sorted(objects), 'keys': dict(sorted(keys.items()))}


def render_inc(schema):
    """One row per key: path, kind, enum/range flags. Included by host/src/configtool.cpp."""
    kinds = {'bool': 'K_BOOL', 'int': 'K_INT', 'real': 'K_REAL', 'string': 'K_STRING', 'strings': 'K_STRINGS', 'list': 'K_LIST', 'any': 'K_ANY'}
    lines = ['// Generated by tools/dev/gen-config-schema.py from the staged Config.qml: do not edit.']
    lines.append('static const SchemaObject SCHEMA_OBJECTS[] = {')
    for o in schema['objects']:
        lines.append(f'\t{{"{o}"}},')
    lines.append('};')
    lines.append('static const SchemaKey SCHEMA_KEYS[] = {')
    for path, e in schema['keys'].items():
        rng = e.get('range')
        enum = e.get('enum')
        lines.append('\t{"%s", %s, %s, %s, %s, {%s}},' % (
            path, kinds[e['kind']],
            'true' if rng else 'false', repr(float(rng[0])) if rng else '0', repr(float(rng[1])) if rng else '0',
            ', '.join(str(v) for v in enum) if enum else ''))
    lines.append('};')
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', required=True)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    schema = build(args.stage)
    json_text = json.dumps(schema, indent=1, ensure_ascii=False) + '\n'
    inc_text = render_inc(schema)
    if args.check:
        bad = []
        for path, text in ((OUT_JSON, json_text), (OUT_INC, inc_text)):
            have = open(path, encoding='utf-8', newline='').read().replace('\r\n', '\n') if os.path.exists(path) else None
            if have != text:
                bad.append(os.path.relpath(path, REPO))
        if bad:
            print('out of date (run tools/dev/gen-config-schema.py --stage <staged ii>): ' + ', '.join(bad))
            return 1
        print(f'config schema current: {len(schema["keys"])} keys, {sum(1 for e in schema["keys"].values() if "range" in e)} ranges, '
              f'{sum(1 for e in schema["keys"].values() if "enum" in e)} enumerations')
        return 0
    for path, text in ((OUT_JSON, json_text), (OUT_INC, inc_text)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
    print(f'wrote {len(schema["keys"])} keys ({sum(1 for e in schema["keys"].values() if "range" in e)} ranges, '
          f'{sum(1 for e in schema["keys"].values() if "enum" in e)} enumerations)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
