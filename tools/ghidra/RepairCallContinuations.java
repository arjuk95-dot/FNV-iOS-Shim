//@category FNV
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.MemoryBlock;
import java.util.*;

/** Recover undecoded fall-through after calls to bodies with a real RET.
 * This is intentionally limited to direct calls within the selected code block.
 * It never clears data or existing instructions, or assumes an import returns.
 * Args: audit|apply code-block callee-address [callee-address...].
 * Supply only callees confirmed by runtime and executable inspection. */
public class RepairCallContinuations extends GhidraScript {
    private boolean hasReturn(Function fn) {
        if (fn == null || fn.isExternal()) return false;
        for (Instruction in : currentProgram.getListing().getInstructions(fn.getBody(), true))
            if (in.getMnemonicString().toUpperCase().startsWith("RET")) return true;
        return false;
    }
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 3 || !(args[0].equals("audit") || args[0].equals("apply")))
            throw new IllegalArgumentException("Expected audit|apply code-block callee-address [callee-address...]");
        boolean apply = args[0].equals("apply");
        String code = args[1];
        Set<Address> allowedCallees = new HashSet<>();
        for (int i=2; i<args.length; i++) allowedCallees.add(toAddr(Long.decode(args[i])));
        Listing listing = currentProgram.getListing();
        FunctionManager fm = currentProgram.getFunctionManager();
        Set<Address> attempted = new HashSet<>();
        int recovered = 0, failed = 0, candidates = 0, repairedTags = 0;
        for (int pass = 0; pass < 8; pass++) {
            Map<Function, Boolean> returns = new HashMap<>();
            TreeSet<Address> pending = new TreeSet<>();
            for (Instruction in : listing.getInstructions(true)) {
                if (!in.getFlowType().isCall() || in.getFlowType().isComputed()) continue;
                Address next = in.getMaxAddress().next();
                MemoryBlock block = currentProgram.getMemory().getBlock(in.getAddress());
                if (next == null || block == null || !block.getName().equals(code) || !block.contains(next)) continue;
                Address[] targets = in.getFlows();
                if (targets.length != 1 || !allowedCallees.contains(targets[0])) continue;
                Function callee = fm.getFunctionAt(targets[0]);
                if (callee == null || !returns.computeIfAbsent(callee, this::hasReturn)) continue;
                if (apply && callee.hasNoReturn()) {
                    println("CLEAR_NORETURN " + callee.getEntryPoint() + " " + callee.getName());
                    callee.setNoReturn(false);
                    repairedTags++;
                }
                if (listing.getInstructionContaining(next) == null && listing.getDefinedDataContaining(next) == null
                    && !attempted.contains(next)) {
                    pending.add(next);
                    if (candidates < 40) println("CANDIDATE " + next + " after " + in.getAddress() + " callee=" + callee.getEntryPoint());
                    candidates++;
                }
            }
            if (!apply || pending.isEmpty()) break;
            for (Address address : pending) {
                attempted.add(address);
                if (listing.getInstructionAt(address) != null) continue;
                DisassembleCommand command = new DisassembleCommand(address, null, true);
                if (command.applyTo(currentProgram, monitor) && listing.getInstructionAt(address) != null) recovered++;
                else failed++;
            }
        }
        println("RepairCallContinuations: apply="+apply+" candidates="+candidates+" recovered="+recovered+" failed="+failed+" noReturnTags="+repairedTags);
    }
}
