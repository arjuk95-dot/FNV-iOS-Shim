//@category FNV
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import java.io.*;
import java.util.*;

/** Read-only coverage census. Args: compiled-entry-list output-json output-gaps-tsv.
 * Counts are analysis evidence, never a claim of complete runtime coverage. */
public class AuditTranslationCoverage extends GhidraScript {
    public void run() throws Exception {
        String[] args=getScriptArgs();
        Set<Long> emitted=new HashSet<>();
        for(String line:java.nio.file.Files.readAllLines(new File(args[0]).toPath()))
            if(!line.trim().isEmpty()) emitted.add(Long.decode(line.trim()));
        Listing listing=currentProgram.getListing();
        FunctionManager fm=currentProgram.getFunctionManager();
        MemoryBlock text=currentProgram.getMemory().getBlock(".text");
        Map<Function,Boolean> returns=new HashMap<>();
        long insns=0, indirect=0, unresolved=0, missingCalls=0, continuations=0, falseNoReturn=0;
        for(Function f:fm.getFunctions(true)) {
            boolean ret=false;
            for(Instruction in:listing.getInstructions(f.getBody(),true))
                if(in.getMnemonicString().toUpperCase().startsWith("RET")){ret=true;break;}
            returns.put(f,ret);
            if(f.hasNoReturn() && ret) falseNoReturn++;
        }
        try(PrintWriter gaps=new PrintWriter(args[2],"UTF-8")) {
            gaps.println("kind\tfrom\ttarget");
            for(Instruction in:listing.getInstructions(true)) {
                if(!text.contains(in.getAddress())) continue;
                insns++;
                if(in.getFlowType().isJump() && in.getFlowType().isComputed()) {
                    indirect++;
                    boolean flow=false;
                    for(Reference r:in.getReferencesFrom()) if(r.getReferenceType().isFlow()) flow=true;
                    if(!flow){unresolved++;gaps.println("unresolved_jump\t"+in.getAddress()+"\t");}
                }
                if(!in.getFlowType().isCall() || in.getFlowType().isComputed()) continue;
                for(Address target:in.getFlows()) {
                    if(!text.contains(target)) continue;
                    if(!emitted.contains(target.getOffset())) {
                        missingCalls++;gaps.println("uncompiled_call_target\t"+in.getAddress()+"\t"+target);
                    }
                    Function callee=fm.getFunctionAt(target);
                    Address next=in.getMaxAddress().next();
                    if(Boolean.TRUE.equals(returns.get(callee)) && next!=null && text.contains(next)
                        && listing.getInstructionAt(next)==null && listing.getDefinedDataContaining(next)==null) {
                        continuations++;gaps.println("undecoded_return_continuation\t"+in.getAddress()+"\t"+next);
                    }
                }
            }
        }
        String json=String.format("{\"compiled_entries\":%d,\"text_instructions\":%d,\"computed_jumps\":%d,\"unresolved_computed_jumps\":%d,\"uncompiled_direct_call_sites\":%d,\"undecoded_return_continuations\":%d,\"no_return_functions_containing_ret\":%d,\"runtime_coverage_proven\":false}",
            emitted.size(),insns,indirect,unresolved,missingCalls,continuations,falseNoReturn);
        try(PrintWriter out=new PrintWriter(args[1],"UTF-8")){out.println(json);}
        println(json);
    }
}
