# Decompile hub

To analyze a file (APK, DEX, JAR, .so, ELF, .exe, .dll):

    ./decompile.sh /full/path/to/file [auto|jadx|ghidra|kuna|rizin|all] [--full]

RULES (saves tokens):
1. This only STARTS the job in the background. After it prints STARTED, STOP.
   Reply with one short sentence ("Started. Tell me when it is finished.").
   Do NOT poll, sleep, watch, or check status.
2. When the user says it is done, run: ./decompile.sh result
3. Read the short summary. Never cat big files; use `grep -rn pattern <dir> | head -40`.
   Only use `result --full` when you need the actual code.
4. Upload, big files, workflow, cached tools and download are all automatic.
   If gh is not logged in, ask the USER to run `gh auth login` themselves.
5. Default is fast (no Ghidra). Use `ghidra` or `all` only when needed.
6. Hopper and IDA are not available.
