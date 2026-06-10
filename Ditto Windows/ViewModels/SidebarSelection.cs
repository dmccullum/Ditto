using Ditto.Models;

namespace Ditto.ViewModels;

public enum SidebarKind { All, Frequent, Category }

/// <summary>What's selected in the sidebar (parity with SidebarSelection in Swift).</summary>
public sealed class SidebarSelection : IEquatable<SidebarSelection>
{
    public SidebarKind Kind { get; }
    public Category? Category { get; }

    private SidebarSelection(SidebarKind kind, Category? category)
    {
        Kind = kind;
        Category = category;
    }

    public static readonly SidebarSelection All = new(SidebarKind.All, null);
    public static readonly SidebarSelection Frequent = new(SidebarKind.Frequent, null);
    public static SidebarSelection ForCategory(Category c) => new(SidebarKind.Category, c);

    public bool Equals(SidebarSelection? other)
        => other != null && Kind == other.Kind && ReferenceEquals(Category, other.Category);

    public override bool Equals(object? obj) => Equals(obj as SidebarSelection);
    public override int GetHashCode() => HashCode.Combine(Kind, Category?.Id ?? 0);
}
