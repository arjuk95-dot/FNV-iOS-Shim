//@category FNV
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

/** Recover unary CRT math records passed in EDX, without assuming pointer alignment.
 * The demonstrated record has a short ASCII name and four pointer fields
 * at +16,+20,+24,+28 selected by an XLAT map containing exactly 0,4,8,12.
 * Args: audit|apply output-json output-extra-entries-json. */
public class ResolveCrtOperationTables extends GhidraScript {
 private Long edxConstantBefore(Instruction flow) {
  Instruction p=flow.getPrevious();
  if(p==null || !p.getMaxAddress().next().equals(flow.getAddress())
     || !p.getMnemonicString().equals("MOV") || !p.getDefaultOperandRepresentation(0).equals("EDX")) return null;
  for(Object o:p.getOpObjects(1)) if(o instanceof Scalar) return ((Scalar)o).getUnsignedValue();
  return null;
 }
 public void run() throws Exception {
  String[] args=getScriptArgs();boolean apply=args[0].equals("apply");
  Listing listing=currentProgram.getListing();FunctionManager fm=currentProgram.getFunctionManager();
  MemoryBlock text=currentProgram.getMemory().getBlock(".text");
  Set<Address> helpers=new HashSet<>(), dispatchJumps=new HashSet<>();ArrayDeque<Address> work=new ArrayDeque<>();
  // FID name is an anchor, not sufficient proof: also verify the unary XLAT map.
  for(Function f:fm.getFunctions(true)) if(f.getName().equals("__trandisp1")) {
   boolean xlat=false,goodMap=false,computed=false;
   for(Instruction in:listing.getInstructions(f.getBody(),true)) {
    if(in.getMnemonicString().equals("XLAT")) xlat=true;
    if(in.getFlowType().isJump()&&in.getFlowType().isComputed()) computed=true;
    if(in.getMnemonicString().equals("MOV")&&in.getDefaultOperandRepresentation(0).equals("EBX"))
     for(Object o:in.getOpObjects(1)) if(o instanceof Scalar) {
      Address map=toAddr(((Scalar)o).getUnsignedValue());
      if(!currentProgram.getMemory().contains(map)) continue;
      Set<Integer> offsets=new HashSet<>();
      for(int i=0;i<16;i++) offsets.add(currentProgram.getMemory().getByte(map.add(i))&255);
      if(offsets.equals(new HashSet<Integer>(Arrays.asList(0,4,8,12)))) goodMap=true;
     }
   }
   if(xlat&&goodMap&&computed){
    helpers.add(f.getEntryPoint());work.add(f.getEntryPoint());
    for(Instruction in:listing.getInstructions(f.getBody(),true))
     if(in.getFlowType().isJump()&&in.getFlowType().isComputed()
        &&in.getDefaultOperandRepresentation(0).contains("[EBX]")) dispatchJumps.add(in.getAddress());
   }
  }
  if(helpers.isEmpty()) throw new IllegalStateException("No structurally verified unary CRT dispatcher");
  TreeMap<Long,Long> records=new TreeMap<>();
  while(!work.isEmpty()&&helpers.size()<64) {
   Address helper=work.remove();
   for(Reference ref:currentProgram.getReferenceManager().getReferencesTo(helper)) {
    Instruction in=listing.getInstructionAt(ref.getFromAddress());
    if(in==null || !(in.getFlowType().isCall()||in.getFlowType().isJump())) continue;
    Long base=edxConstantBefore(in);
    if(base!=null){records.put(base,in.getAddress().getOffset());continue;}
    Function owner=fm.getFunctionContaining(in.getAddress());
    if(owner!=null && owner.getName().toLowerCase().contains("disp") && helpers.add(owner.getEntryPoint())) work.add(owner.getEntryPoint());
   }
  }
  Set<Long> targets=new TreeSet<>();TreeMap<Long,Set<Long>> extras=new TreeMap<>();
  int valid=0,created=0,decoded=0;ArrayList<String> evidence=new ArrayList<>();
  for(Map.Entry<Long,Long> record:records.entrySet()) {
   Address base=toAddr(record.getKey());MemoryBlock block=currentProgram.getMemory().getBlock(base);
   if(block==null||!block.isInitialized()||!block.contains(base.add(31))) continue;
   int length=currentProgram.getMemory().getByte(base)&255;
   println("RECORD_CANDIDATE base="+base+" reference="+toAddr(record.getValue())+" name_length="+length+" header13="+(currentProgram.getMemory().getByte(base.add(13))&255));
   if(length<1||length>10) continue;
   StringBuilder name=new StringBuilder();boolean ascii=true;
   for(int i=0;i<length;i++){int ch=currentProgram.getMemory().getByte(base.add(i+1))&255;if(ch<32||ch>126)ascii=false;name.append((char)ch);}
   if(!ascii)continue;
   long[] entries=new long[4];boolean good=true;
   for(int i=0;i<4;i++){entries[i]=currentProgram.getMemory().getInt(base.add(16+4*i))&0xffffffffL;if(!text.contains(toAddr(entries[i])))good=false;}
   if(!good)continue;valid++;
   evidence.add(String.format("{\"base\":%d,\"reference\":%d,\"name\":\"%s\",\"alignment\":%d,\"targets\":%s}",record.getKey(),record.getValue(),name.toString(),record.getKey()%4,Arrays.toString(entries)));
   for(long value:entries) {
    targets.add(value);if(!apply)continue;Address a=toAddr(value);
    Instruction existing=listing.getInstructionContaining(a);
    if(existing!=null&&!existing.getAddress().equals(a))throw new IllegalStateException("Target lies inside instruction "+a);
    if(listing.getInstructionAt(a)==null) {
     if(listing.getDefinedDataContaining(a)!=null)throw new IllegalStateException("Target overlaps defined data "+a);
     if(!new DisassembleCommand(a,null,true).applyTo(currentProgram,monitor)||listing.getInstructionAt(a)==null)throw new IllegalStateException("Cannot decode proven table target "+a);
     decoded++;
    }
    Function owner=fm.getFunctionContaining(a);
    if(fm.getFunctionAt(a)==null&&owner==null) {
     if(!new CreateFunctionCmd(a).applyTo(currentProgram,monitor))throw new IllegalStateException("Cannot define target "+a);
     created++;
    }else if(owner!=null&&!owner.getEntryPoint().equals(a))extras.computeIfAbsent(owner.getEntryPoint().getOffset(),k->new TreeSet<>()).add(value);
   }
  }
  // Export these proven destinations as CFG edges, preserving live flag/register context.
  if(apply)for(Address jump:dispatchJumps)for(long target:targets)
   currentProgram.getReferenceManager().addMemoryReference(jump,toAddr(target),RefType.COMPUTED_JUMP,SourceType.ANALYSIS,0);
  try(PrintWriter out=new PrintWriter(args[1],"UTF-8")){out.printf("{\"applied\":%s,\"helpers\":%d,\"candidate_records\":%d,\"valid_records\":%d,\"unique_targets\":%d,\"decoded_roots\":%d,\"created_functions\":%d,\"records\":[%s]}\n",apply,helpers.size(),records.size(),valid,targets.size(),decoded,created,String.join(",",evidence));}
  try(PrintWriter out=new PrintWriter(args[2],"UTF-8")){out.print("{");boolean first=true;for(Map.Entry<Long,Set<Long>> e:extras.entrySet()){if(!first)out.print(',');first=false;out.print("\""+e.getKey()+"\":"+e.getValue().toString());}out.print("}");}
  println("Unary CRT operation records="+valid+" unique targets="+targets.size()+" decoded="+decoded+" created="+created);
 }
}
