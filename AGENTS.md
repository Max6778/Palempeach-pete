# Decompile hub

To analyze any file (APK, DEX, JAR, .so, ELF, .exe, .dll), run:

    ./decompile.sh /full/path/to/file

It uploads the file to GitHub Actions and downloads the result into
./out/<filename>/. Read the files in that folder.

Tools: JADX and Apktool (Android), Ghidra, Kuna, Rizin, ILSpy (.NET), plus an
info step that always runs (file type, strings, headers, engine hints).
Add `jadx`, `ghidra`, `kuna`, `rizin` or `all` as a second argument to force
tools. Hopper and IDA are not available here (paid, no headless mode).

Start with out/<filename>/info/engine-hints.txt to see which engine a program uses.
