using System;
using System.Collections.Generic;
using System.Linq;
using PassAiFire.Core;

internal static class Program
{
    private static int failures;
    private static int checks;
    private static void Check(string name, bool ok)
    {
        checks++; if (!ok) failures++;
        Console.WriteLine((ok ? "PASS " : "FAIL ") + name);
    }
    private static bool Reject<T>(Action action) where T : Exception
    {
        try { action(); return false; } catch (T) { return true; }
    }
    private static int Main()
    {
        var catalog = FeatureCatalog.Load();
        Check("official tracking manifest loaded", catalog.Requirements.Count == 76);
        Check("stable ids unique", catalog.Requirements.Select(r => r.Id).Distinct().Count() == 76);
        Check("all future features disabled", catalog.ImplementedCount == 0 && catalog.Requirements.All(r => !r.Implemented));
        foreach (var item in catalog.Requirements)
            Check("planned feature cannot execute " + item.Id, Reject<NotSupportedException>(() => catalog.Execute(item.Id)));
        Check("unknown id fails closed", Reject<ArgumentException>(() => catalog.Execute("SPK")));
        Check("null id fails closed", Reject<ArgumentException>(() => catalog.Execute(null!)));
        Check("case variant fails closed", Reject<ArgumentException>(() => catalog.Execute("fire-com-001")));
        Check("domain mismatch rejected", Reject<ArgumentException>(() => new Requirement("FIRE-COM-001", "MECH", "test")));
        Check("malformed id rejected", Reject<ArgumentException>(() => new Requirement("FIRE-COM-../1", "COM", "test")));
        Check("trailing newline id rejected", Reject<ArgumentException>(() => new Requirement("FIRE-COM-001\n", "COM", "test")));
        Check("empty executable id rejected", Reject<ArgumentException>(() => catalog.Execute("")));
        Check("empty title rejected", Reject<ArgumentException>(() => new Requirement("FIRE-COM-001", "COM", " ")));
        Check("null catalog rejected", Reject<ArgumentNullException>(() => new FeatureCatalog(null!)));
        var requirement = new Requirement("FIRE-COM-001", "COM", "test");
        Check("duplicate ids rejected", Reject<ArgumentException>(() => new FeatureCatalog(new[] { requirement, requirement })));
        Check("null item rejected", Reject<ArgumentException>(() => new FeatureCatalog(new Requirement[] { null! })));
        var original = new List<Requirement> { requirement };
        var snapshot = new FeatureCatalog(original); original.Clear();
        Check("catalog owns immutable snapshot", snapshot.Requirements.Count == 1);
        Check("public collection rejects mutation", Reject<NotSupportedException>(() => ((IList<Requirement>)snapshot.Requirements).Clear()));
        Check("core has no CAD reference", !typeof(FeatureCatalog).Assembly.GetReferencedAssemblies().Any(a => a.Name.StartsWith("Ac", StringComparison.Ordinal)));
        Check("host distinct from requirements", FoundationInfo.Host == "AutoCAD2024/net48/x64" && FoundationInfo.TargetRequirements == "FIRE2025+");
        Check("diagnostic reports disabled", FoundationInfo.Status(catalog).Contains("implemented=0") && FoundationInfo.Status(catalog).Contains("features=DISABLED"));
        Console.WriteLine("FIRE_TEST_RESULT checks=" + checks + " failed=" + failures);
        return failures == 0 ? 0 : 1;
    }
}
