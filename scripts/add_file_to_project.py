#!/usr/bin/env python3
import sys
import hashlib
import os

def generate_id(seed_prefix, filename):
    h = hashlib.md5(f"{seed_prefix}_{filename}".encode('utf-8')).hexdigest().upper()
    return "AD" + h[:22]

def add_file(filepath):
    pbx_path = "NotchDrop.xcodeproj/project.pbxproj"
    if not os.path.exists(pbx_path):
        print(f"Error: {pbx_path} not found")
        sys.exit(1)

    filename = os.path.basename(filepath)
    is_test = filepath.startswith("Tests/") or "Tests.swift" in filename

    with open(pbx_path, "r", encoding="utf-8") as f:
        content = f.read()

    if f"/* {filename} */" in content:
        print(f"{filename} already present in project.pbxproj")
        return

    build_file_id = generate_id("BF", filename)
    file_ref_id = generate_id("FR", filename)

    # 1. PBXBuildFile section
    build_file_entry = f"\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};\n"
    marker = "/* Begin PBXBuildFile section */\n"
    if marker in content:
        content = content.replace(marker, marker + build_file_entry)
    else:
        print("Error: PBXBuildFile section not found")
        sys.exit(1)

    # 2. PBXFileReference section
    file_ref_entry = f"\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    marker = "/* Begin PBXFileReference section */\n"
    if marker in content:
        content = content.replace(marker, marker + file_ref_entry)
    else:
        print("Error: PBXFileReference section not found")
        sys.exit(1)

    # 3. PBXGroup children
    if is_test:
        group_marker = "7AE10C0220260AB0000000A6 /* Tests */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        child_entry = f"\t\t\t\t{file_ref_id} /* {filename} */,\n"
        if group_marker in content:
            content = content.replace(group_marker, group_marker + child_entry)
        else:
            print("Error: Tests PBXGroup not found")
            sys.exit(1)
    else:
        group_marker = "504381822C3A86EA000ED325 /* NotchDrop */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        child_entry = f"\t\t\t\t{file_ref_id} /* {filename} */,\n"
        if group_marker in content:
            content = content.replace(group_marker, group_marker + child_entry)
        else:
            print("Error: NotchDrop PBXGroup not found")
            sys.exit(1)

    # 4. Sources Build Phase
    if is_test:
        sources_marker = "7AE10C0220260AB0000000A5 /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
        source_entry = f"\t\t\t\t{build_file_id} /* {filename} in Sources */,\n"
        if sources_marker in content:
            content = content.replace(sources_marker, sources_marker + source_entry)
        else:
            print("Error: Tests PBXSourcesBuildPhase not found")
            sys.exit(1)
    else:
        sources_marker = "5043817C2C3A86EA000ED325 /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
        source_entry = f"\t\t\t\t{build_file_id} /* {filename} in Sources */,\n"
        if sources_marker in content:
            content = content.replace(sources_marker, sources_marker + source_entry)
        else:
            print("Error: NotchDrop PBXSourcesBuildPhase not found")
            sys.exit(1)

    with open(pbx_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Successfully added {filename} to project.pbxproj ({'Tests' if is_test else 'NotchDrop'})")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/add_file_to_project.py <filepath>")
        sys.exit(1)
    for arg in sys.argv[1:]:
        add_file(arg)
