using Mono.Cecil;
var path = args[0];
var resolver = new DefaultAssemblyResolver();
resolver.AddSearchDirectory(Path.GetDirectoryName(path)!);
var asm = AssemblyDefinition.ReadAssembly(path, new ReaderParameters { AssemblyResolver = resolver, ReadSymbols = false });
foreach (var type in asm.MainModule.Types.Where(t => t.FullName.Contains("Symbols") || t.Name == "SymbolBase" || t.Name.Contains("Sec")))
{
  Console.WriteLine("TYPE " + type.FullName);
  foreach (var m in type.Methods.Take(30))
  {
    var rva = m.RVA;
    var size = m.HasBody ? m.Body.CodeSize : -1;
    var instr = m.HasBody ? m.Body.Instructions.Count : 0;
    Console.WriteLine($"  {m.Name} RVA={rva} CodeSize={size} Instr={instr} Impl={m.ImplAttributes} Attr={m.Attributes}");
  }
}
