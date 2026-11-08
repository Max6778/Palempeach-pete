import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;

public class DecompileAll extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        File out = new File(a.length > 0 ? a[0] : "decompiled.c");
        File idx = new File(out.getParentFile(), "functions.txt");
        DecompInterface ifc = new DecompInterface();
        ifc.openProgram(currentProgram);
        try (PrintWriter w = new PrintWriter(out); PrintWriter x = new PrintWriter(idx)) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                x.println(f.getEntryPoint() + " " + f.getName() + " " + f.getBody().getNumAddresses());
                DecompileResults r = ifc.decompileFunction(f, 60, monitor);
                if (r.decompileCompleted()) {
                    w.println(r.getDecompiledFunction().getC());
                }
            }
        }
    }
}
