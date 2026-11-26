#!/usr/bin/env python3
import re
from pathlib import Path, PurePosixPath

project_file = Path(__file__).resolve().parent.parent / "RoweIOS.xcodeproj" / "project.pbxproj"
text = project_file.read_text()

reference_pattern = re.compile(
    r'(?m)^\s*([0-9A-Fa-f]{24}) /\* XCLocalSwiftPackageReference "([^"]+)" \*/ = \{\n'
    r'\s*isa = XCLocalSwiftPackageReference;\n'
    r'\s*relativePath = ([^;]+);\n'
    r'\s*\};'
)
references = {}
for match in reference_pattern.finditer(text):
    object_id, label, relative_path = match.groups()
    references[PurePosixPath(relative_path.strip()).name] = (object_id, label)

product_pattern = re.compile(
    r'(?ms)^\s*[0-9A-Fa-f]{24} /\* [^\n]+ \*/ = \{\n'
    r'\s*isa = XCSwiftPackageProductDependency;\n'
    r'.*?^\s*\};'
)


def repair(match):
    block = match.group(0)
    if re.search(r'(?m)^\s*package\s*=', block):
        return block
    product = re.search(r'(?m)^\s*productName = ([^;]+);', block)
    if not product:
        return block
    reference = references.get(product.group(1).strip())
    if not reference:
        return block
    object_id, label = reference
    isa = re.search(r'(?m)^([ \t]*)isa = XCSwiftPackageProductDependency;', block)
    indent = isa.group(1)
    dependency = f'{indent}isa = XCSwiftPackageProductDependency;\n'
    replacement = (
        dependency
        + f'{indent}package = {object_id} /* XCLocalSwiftPackageReference "{label}" */;\n'
    )
    return block.replace(dependency, replacement, 1)


repaired = product_pattern.sub(repair, text)
if repaired != text:
    project_file.write_text(repaired)
    print("Fixed local Swift package product backlinks")
