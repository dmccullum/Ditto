using Microsoft.EntityFrameworkCore;

namespace Ditto.Models;

/// <summary>
/// SQLite-backed store. The database lives at
/// %APPDATA%\Ditto\ditto.db. This is the Windows analogue of the SwiftData
/// ModelContainer — local only, no CloudKit sync.
/// </summary>
public class DittoDbContext : DbContext
{
    public DbSet<Snippet> Snippets => Set<Snippet>();
    public DbSet<Category> Categories => Set<Category>();

    public static string DatabasePath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ditto");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "ditto.db");
        }
    }

    protected override void OnConfiguring(DbContextOptionsBuilder options)
        => options.UseSqlite($"Data Source={DatabasePath}");

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Category>()
            .HasMany(c => c.Snippets)
            .WithOne(s => s.Category!)
            .HasForeignKey(s => s.CategoryId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
