using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace PassAiFire.Core
{
    public sealed class Requirement
    {
        public string Id { get; }
        public string Domain { get; }
        public string Title { get; }
        public bool Implemented => false;
        public Requirement(string id, string domain, string title)
        {
            if (id == null || !Regex.IsMatch(id, @"\AFIRE-(COM|MECH|ELEC|UTIL|EXTRA)-[0-9]{3}\z"))
                throw new ArgumentException("Invalid stable requirement id.", nameof(id));
            if (domain == null || !id.StartsWith("FIRE-" + domain + "-", StringComparison.Ordinal))
                throw new ArgumentException("Requirement domain mismatch.", nameof(domain));
            if (string.IsNullOrWhiteSpace(title)) throw new ArgumentException("Title is required.", nameof(title));
            Id = id; Domain = domain; Title = title;
        }
    }

    public sealed class FeatureCatalog
    {
        public ReadOnlyCollection<Requirement> Requirements { get; }
        public int ImplementedCount => 0;
        public FeatureCatalog(IEnumerable<Requirement> requirements)
        {
            if (requirements == null) throw new ArgumentNullException(nameof(requirements));
            var owned = requirements.ToArray();
            if (owned.Any(r => r == null) || owned.Select(r => r.Id).Distinct(StringComparer.Ordinal).Count() != owned.Length)
                throw new ArgumentException("Null or duplicate requirement.", nameof(requirements));
            Requirements = Array.AsReadOnly(owned);
        }
        public static FeatureCatalog Load()
        {
            using (var stream = typeof(FeatureCatalog).Assembly.GetManifestResourceStream("PassAiFire.Core.Catalog.tsv"))
            {
                if (stream == null) throw new InvalidOperationException("Catalog resource missing.");
                using (var reader = new StreamReader(stream))
                {
                    var items = new List<Requirement>();
                    string? line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        var fields = line.Split('\t');
                        if (fields.Length != 3) throw new InvalidDataException("Catalog row must have three fields.");
                        items.Add(new Requirement(fields[0], fields[1], fields[2]));
                    }
                    return new FeatureCatalog(items);
                }
            }
        }
        public void Execute(string id)
        {
            if (!Requirements.Any(r => string.Equals(r.Id, id, StringComparison.Ordinal)))
                throw new ArgumentException("Unknown requirement.", nameof(id));
            throw new NotSupportedException("Feature development has not started; detailed specification approval required.");
        }
    }

    public static class FoundationInfo
    {
        public static string Version => typeof(FoundationInfo).Assembly.GetName().Version.ToString(3);
        public const string Host = "AutoCAD2024/net48/x64";
        public const string TargetRequirements = "FIRE2025+";
        public static string About => "PASS_AI_FIRE " + Version + " | " + Host + " | foundation-only";
        public static string Status(FeatureCatalog catalog) => "PASS_AI_FIRE_STATUS tracked=" + catalog.Requirements.Count
            + " implemented=" + catalog.ImplementedCount + " target=" + TargetRequirements + " features=DISABLED";
    }
}
