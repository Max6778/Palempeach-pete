#!/usr/bin/env bash
# Builds a SHORT summary so the agent does not need to read huge outputs
cd "$(dirname "$0")/.."
O=out; mkdir -p "$O"; S="$O/summary.md"
{
echo "# Summary: ${TARGET_INPUT}"
echo
echo "Tool status: info=$R_INFO jadx=$R_JADX apktool=$R_APKTOOL ghidra=$R_GHIDRA kuna=$R_KUNA"
echo
if [ -f $O/info/file.txt ]; then echo "## File"; cat $O/info/file.txt; echo; fi
if [ -s $O/info/engine-hints.txt ]; then echo "## Engine hints (first 15)"; head -n 15 $O/info/engine-hints.txt | cut -c1-200; echo; fi
if [ -s $O/info/imports.txt ]; then echo "## Imports (first 30)"; head -n 30 $O/info/imports.txt | cut -c1-160; echo; fi
if [ -f $O/apktool/AndroidManifest.xml ]; then
  echo "## Android manifest"
  grep -o 'package="[^"]*"' $O/apktool/AndroidManifest.xml | head -1
  grep -o 'uses-permission[^/]*android:name="[^"]*"' $O/apktool/AndroidManifest.xml | sed 's/.*name="//;s/"//' | head -30
  echo
fi
if [ -d $O/jadx ]; then
  echo "## JADX"
  echo "java files: $(find $O/jadx -name '*.java' | wc -l)"
  echo "top packages:"
  find $O/jadx/sources -mindepth 1 -maxdepth 3 -type d 2>/dev/null | sed "s|$O/jadx/sources/||" | head -30
  echo
fi
if [ -f $O/ghidra/functions.txt ]; then
  echo "## Ghidra"
  echo "functions: $(wc -l < $O/ghidra/functions.txt)  (columns: address name size)"
  echo "largest 15:"; sort -k3 -n -r $O/ghidra/functions.txt | head -15
  echo
fi
if [ -f $O/rizin/functions.txt ]; then echo "## Rizin"; echo "functions listed: $(wc -l < $O/rizin/functions.txt)"; echo; fi
if [ -d $O/kuna ]; then echo "## Kuna files"; ls $O/kuna | head -20; echo; fi
echo "## Folder sizes"; du -sh $O/*/ 2>/dev/null
echo
echo "## How to search (do not cat big files)"
echo "grep -rn 'pattern' <folder> | head -40"
} > "$S"
echo "Summary written: $S ($(wc -l < "$S") lines)"
