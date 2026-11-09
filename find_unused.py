import os
import re

# ============================================================
# FIND UNUSED CODE
# Run it in the project folder (the one that contains "lib").
# It only READS your files. It never changes or deletes anything.
#
# It lists:
#  1. Classes that nothing else in the lib folder uses
#  2. Functions whose name starts with "old"
# ============================================================

LIB = "lib"

# Read every .dart file in the lib folder
files = {}
for name in sorted(os.listdir(LIB)):
    if name.endswith(".dart"):
        with open(os.path.join(LIB, name), encoding="utf-8") as f:
            files[name] = f.read()

# Remove // comments (line numbers stay the same, because only the
# comment text is removed and the line breaks are kept)
def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)

clean = {name: strip_comments(text) for name, text in files.items()}


# Finds where a class ends, by matching its curly braces
def class_span(text, start):
    open_at = text.find("{", start)
    if open_at == -1:
        return start, start

    depth = 0
    i = open_at

    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
        i += 1

    return start, len(text)


def line_of(text, position):
    return text.count("\n", 0, position) + 1


unused = []

for file_name, text in clean.items():
    for match in re.finditer(r"^(?:abstract\s+)?class\s+(\w+)", text, re.M):
        name = match.group(1)

        # Private helper classes (like _SomethingState) are handled
        # together with the class that owns them
        if name.startswith("_"):
            continue

        start, end = class_span(text, match.start())

        # Count the uses of this name OUTSIDE the class's own body
        uses = 0
        for other_name, other_text in clean.items():
            body = other_text
            if other_name == file_name:
                body = other_text[:start] + other_text[end:]
            uses += len(re.findall(r"\b" + re.escape(name) + r"\b", body))

        if uses == 0:
            state_name = "_" + name + "State"
            state_line = None

            for s in re.finditer(r"^class\s+" + state_name + r"\b", text, re.M):
                state_line = (line_of(text, s.start()),
                              line_of(text, class_span(text, s.start())[1]))

            unused.append((
                file_name,
                name,
                line_of(text, start),
                line_of(text, end),
                state_line,
            ))

print()
print("=== CLASSES THAT NOTHING ELSE USES ===")

if not unused:
    print("None found.")

for file_name, name, first, last, state_line in unused:
    print(f"lib/{file_name}: {name}   lines {first} to {last}")
    if state_line:
        print(f"      its state class _{name}State   lines {state_line[0]} to {state_line[1]}")

print()
print("=== FUNCTIONS WHOSE NAME STARTS WITH 'old' ===")

found_old = False

for file_name, text in clean.items():
    for match in re.finditer(r"\b(_?old[A-Z]\w*)\s*\(", text):
        found_old = True
        print(f"lib/{file_name}: {match.group(1)}   line {line_of(text, match.start())}")

if not found_old:
    print("None found.")

print()
print("Nothing was changed. Check each item before you delete it.")