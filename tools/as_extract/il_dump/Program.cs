using System.Text;
using Mono.Cecil;
using Mono.Cecil.Cil;

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: il_dump <dll> <outDir> [typeSubstring]");
    return 1;
}

var dllPath = args[0];
var outDir = args[1];
var filter = args.Length > 2 ? args[2] : "";
Directory.CreateDirectory(outDir);

var resolver = new DefaultAssemblyResolver();
resolver.AddSearchDirectory(Path.GetDirectoryName(dllPath)!);
var readerParams = new ReaderParameters { AssemblyResolver = resolver };
using var asm = AssemblyDefinition.ReadAssembly(dllPath, readerParams);

var sbIndex = new StringBuilder();
sbIndex.AppendLine($"// {dllPath}");
foreach (var type in asm.MainModule.Types.OrderBy(t => t.FullName))
{
    if (filter != "" && type.FullName.IndexOf(filter, StringComparison.OrdinalIgnoreCase) < 0)
        continue;
    var methodsWithBody = type.Methods.Count(m => m.HasBody && m.Body.Instructions.Count > 1);
    var floats = 0;
    foreach (var m in type.Methods.Where(m => m.HasBody))
        floats += m.Body.Instructions.Count(i => i.OpCode.Code == Code.Ldc_R4 || i.OpCode.Code == Code.Ldc_R8);
    sbIndex.AppendLine($"{type.FullName}\tmethods_with_body={methodsWithBody}\tfloat_consts={floats}");

    if (methodsWithBody == 0) continue;
    if (filter == "" && floats < 8) continue;

    var safe = type.Name.Replace('<', '_').Replace('>', '_');
    var sb = new StringBuilder();
    sb.AppendLine($"// {type.FullName}");
    foreach (var method in type.Methods.Where(m => m.HasBody && m.Body.Instructions.Count > 1))
    {
        var hasFloat = method.Body.Instructions.Any(i => i.OpCode.Code is Code.Ldc_R4 or Code.Ldc_R8);
        if (filter == "" && !hasFloat && method.Body.Instructions.Count < 30) continue;
        sb.AppendLine();
        sb.AppendLine($"// {method.FullName} instr={method.Body.Instructions.Count}");
        foreach (var ins in method.Body.Instructions)
            sb.AppendLine($"  {ins.OpCode} {FormatOperand(ins)}");
    }
    File.WriteAllText(Path.Combine(outDir, safe + ".il.txt"), sb.ToString(), Encoding.UTF8);
}

File.WriteAllText(Path.Combine(outDir, "_index.txt"), sbIndex.ToString(), Encoding.UTF8);
Console.WriteLine("Done.");
return 0;

static string FormatOperand(Instruction ins)
{
    if (ins.Operand == null) return "";
    return ins.Operand switch
    {
        double d => d.ToString(System.Globalization.CultureInfo.InvariantCulture),
        float f => f.ToString(System.Globalization.CultureInfo.InvariantCulture),
        _ => ins.Operand.ToString() ?? ""
    };
}
