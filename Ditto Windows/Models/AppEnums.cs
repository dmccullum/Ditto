namespace Ditto.Models;

/// <summary>What to do with a shared link's category when importing it.</summary>
public enum LinkCategoryBehavior { Keep, Uncategorized }

/// <summary>How the All Snippets view groups its cards.</summary>
public enum SnippetGrouping { None, Category, DateAdded }

public static class EnumLabels
{
    public static string Label(this LinkCategoryBehavior b) => b switch
    {
        LinkCategoryBehavior.Keep => "Keep their category",
        LinkCategoryBehavior.Uncategorized => "Import as uncategorized",
        _ => b.ToString()
    };

    public static string Label(this SnippetGrouping g) => g switch
    {
        SnippetGrouping.None => "None",
        SnippetGrouping.Category => "Category",
        SnippetGrouping.DateAdded => "Date Added",
        _ => g.ToString()
    };
}
