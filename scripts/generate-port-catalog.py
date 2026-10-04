#!/usr/bin/env python3
"""Generate Bus Stop's port-location catalogue from PortScope's data.

Usage:
    scripts/generate-port-catalog.py path/to/MacPortLocations.json [output.swift]

Reads PortScope's MacPortLocations.json (https://github.com/azenla/portscope,
MIT License, (c) 2026 Alex Zenla) and writes
Sources/BusStopCore/Labels/PortLocationCatalog+Data.swift: one
MachineCatalogEntry per model, sorted by model identifier, with each model's
ports in the order the JSON lists them.

The output is deterministic: the same input always produces the same bytes.
It uses only the Python standard library.

Connector names are kept as PortScope spells them, except "sd-card", which is
written as "sd" to match PortKind.catalogConnector in BusStopCore.
"""

import json
import os
import sys
import textwrap

SOURCE_URL = "https://github.com/azenla/portscope"
SOURCE_FILE = "MacPortLocations.json"
SOURCE_LICENSE = "MIT License, © 2026 Alex Zenla"
SUPPORTED_SCHEMA = 1

# PortScope connector names that Bus Stop spells differently.
CONNECTOR_RENAMES = {"sd-card": "sd"}

DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    os.pardir,
    "Sources",
    "BusStopCore",
    "Labels",
    "PortLocationCatalog+Data.swift",
)


def fail(message):
    sys.stderr.write("generate-port-catalog: " + message + "\n")
    sys.exit(1)


def swift_string(value):
    """A Swift string literal for `value`, escaping what Swift requires."""
    out = []
    for ch in value:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F:
            out.append("\\u{%X}" % code)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def optional_string(value):
    if value is None:
        return "nil"
    return swift_string(value)


def require_string(value, what):
    if not isinstance(value, str) or not value.strip():
        fail("%s must be a non-empty string, got %r" % (what, value))
    return value.strip()


def optional_text(value, what):
    if value is None:
        return None
    if not isinstance(value, str):
        fail("%s must be a string, got %r" % (what, value))
    value = value.strip()
    return value or None


def require_int(value, what):
    # bool is a subclass of int in Python; reject it explicitly.
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        fail("%s must be a non-negative integer, got %r" % (what, value))
    return value


def comment_block(label, text):
    """`text` wrapped into `//` comment lines under a label."""
    lines = ["// " + label + ":"]
    for line in textwrap.wrap(" ".join(text.split()), width=96):
        lines.append("//   " + line)
    return lines


def load_models(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, ValueError) as error:
        fail("cannot read %s: %s" % (path, error))

    if not isinstance(document, dict):
        fail("top level must be an object")
    schema = document.get("$schema_version")
    if schema != SUPPORTED_SCHEMA:
        fail("unsupported $schema_version %r (expected %d)" % (schema, SUPPORTED_SCHEMA))
    models = document.get("models")
    if not isinstance(models, dict) or not models:
        fail("'models' must be a non-empty object")

    entries = []
    for model in sorted(models):
        info = models[model]
        where = "models[%r]" % model
        if not isinstance(info, dict):
            fail(where + " must be an object")
        marketing = require_string(info.get("marketing_name"), where + ".marketing_name")
        chassis = optional_text(info.get("chassis"), where + ".chassis")
        raw_ports = info.get("ports")
        if not isinstance(raw_ports, list):
            fail(where + ".ports must be an array")
        ports = []
        seen = set()
        for index, port in enumerate(raw_ports):
            pwhere = "%s.ports[%d]" % (where, index)
            if not isinstance(port, dict):
                fail(pwhere + " must be an object")
            connector = require_string(port.get("connector"), pwhere + ".connector").lower()
            connector = CONNECTOR_RENAMES.get(connector, connector)
            number = require_int(port.get("port_number"), pwhere + ".port_number")
            location = require_string(port.get("location"), pwhere + ".location")
            capability = optional_text(port.get("capability"), pwhere + ".capability")
            if (connector, number) in seen:
                fail("%s duplicates %s #%d" % (pwhere, connector, number))
            seen.add((connector, number))
            ports.append((connector, number, location, capability))
        entries.append((require_string(model, where), marketing, chassis, ports))
    return document, entries


def render(document, entries):
    lines = [
        "// Port locations per Mac model.",
        "//",
        "// Source: %s, %s" % (SOURCE_URL, SOURCE_FILE),
        "// %s. See THIRD_PARTY_NOTICES.md." % SOURCE_LICENSE,
        "//",
        "// Generated by scripts/generate-port-catalog.py. Do not edit by hand.",
        "//",
    ]
    doc = document.get("$doc")
    if isinstance(doc, str) and doc.strip():
        lines += comment_block("Numbering conventions (from the source's $doc)", doc)
        lines.append("//")
    note = document.get("$mbp_chassis_note")
    if isinstance(note, str) and note.strip():
        lines += comment_block("MacBook Pro chassis note (from the source's $mbp_chassis_note)", note)
        lines.append("//")
    port_count = sum(len(ports) for _, _, _, ports in entries)
    lines += [
        "// %d models, %d ports. \"sd-card\" is written as \"sd\" to match PortKind.catalogConnector." % (
            len(entries), port_count),
        "",
        "extension PortLocationCatalog {",
        "    /// Every catalogued model, sorted by `hw.model`.",
        "    static let generatedEntries: [MachineCatalogEntry] = [",
    ]
    for model, marketing, chassis, ports in entries:
        lines.append("        MachineCatalogEntry(model: %s, marketingName: %s," % (
            swift_string(model), swift_string(marketing)))
        lines.append("                            chassis: %s, ports: [" % optional_string(chassis))
        for connector, number, location, capability in ports:
            lines.append("            row(%s, %d, %s, %s)," % (
                swift_string(connector), number, swift_string(location), optional_string(capability)))
        lines.append("        ]),")
    lines += [
        "    ]",
        "",
        "    /// One catalogue row. A plain function keeps each line short and the",
        "    /// array literal cheap to type-check.",
        "    private static func row(_ connector: String, _ number: Int, _ location: String,",
        "                            _ capability: String?) -> PortLocationEntry {",
        "        PortLocationEntry(connector: connector, portNumber: number, location: location, capability: capability)",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def main(argv):
    if len(argv) not in (2, 3) or argv[1] in ("-h", "--help"):
        sys.stderr.write(__doc__)
        return 2 if len(argv) not in (2, 3) else 0
    document, entries = load_models(argv[1])
    output = argv[2] if len(argv) == 3 else os.path.normpath(DEFAULT_OUTPUT)
    text = render(document, entries)
    with open(output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    sys.stdout.write("Wrote %d models to %s\n" % (len(entries), output))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
