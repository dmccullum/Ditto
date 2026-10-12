namespace Ditto.Models;

/// <summary>
/// Maps the stored SF Symbol identifiers to glyphs in "Segoe MDL2 Assets",
/// the icon font that ships with Windows 10/11. The SF names remain the stored
/// identity (so JSON exports stay portable to the Apple apps); we only swap to
/// a glyph at render time. Code points are kept as ints and converted on demand
/// so the source file stays plain ASCII. Unknown names fall back to a tag glyph.
/// </summary>
public static class SymbolMap
{
    public const string FontFamily = "Segoe MDL2 Assets";

    private const int Fallback = 0xE8EC; // Tag

    // SF Symbol identifier -> Segoe MDL2 Assets code point.
    private static readonly Dictionary<string, int> _map = new()
    {
        // Text & writing
        ["textformat"]        = 0xE8D2, // Font
        ["paragraph"]         = 0xE8E4, // AlignLeft
        ["square.and.pencil"] = 0xE70F, // Edit
        ["note.text"]         = 0xE70B, // QuickNote
        ["text.alignleft"]    = 0xE8E4, // AlignLeft
        ["text.cursor"]       = 0xE70F, // Edit
        ["signature"]         = 0xE929, // PenWorkspace
        ["character"]         = 0xE8D2, // Font
        // Code & technical
        ["curlybraces"]       = 0xE943, // Code
        ["terminal.fill"]     = 0xE756, // CommandPrompt
        ["function"]          = 0xE8EF, // Calculator
        ["command"]           = 0xE756, // CommandPrompt
        ["keyboard"]          = 0xE765, // Keyboard
        // Lists & structure
        ["list.bullet"]       = 0xE8FD, // BulletedList
        ["list.number"]       = 0xEA37, // List
        ["checklist"]         = 0xE73A, // CheckboxComposite
        ["list.clipboard"]    = 0xE77F, // Paste
        // Documents
        ["doc.text.fill"]     = 0xE8A5, // Document
        ["doc.text"]          = 0xE8A5, // Document
        ["text.quote"]        = 0xE90A, // Comment
        ["number"]            = 0xE8EF, // Calculator (numeric)
        // Links & social
        ["link"]              = 0xE71B, // Link
        ["at"]                = 0xE715, // Mail
        ["bubble.left.fill"]  = 0xE8BD, // Message
        ["megaphone.fill"]    = 0xE789, // Megaphone
        ["envelope.fill"]     = 0xE715, // Mail
        // Creative & content
        ["wand.and.stars"]    = 0xE945, // LightningBolt
        ["sparkles"]          = 0xE706, // Brightness
        ["arrow.triangle.2.circlepath"] = 0xE895, // Sync
        ["paintpalette.fill"] = 0xE790, // Color
        ["camera.fill"]       = 0xE722, // Camera
        ["music.note"]        = 0xE8D6, // MusicInfo
        // Organisation
        ["tag.fill"]          = 0xE8EC, // Tag
        ["bookmark.fill"]     = 0xE8A4, // Bookmarks
        ["star.fill"]         = 0xE735, // FavoriteStarFill
        ["heart.fill"]        = 0xEB52, // HeartFill
        ["bolt.fill"]         = 0xE945, // LightningBolt
        ["flame.fill"]        = 0xE945, // LightningBolt (no flame in MDL2)
        ["calendar"]          = 0xE787, // Calendar
        ["clock"]             = 0xE917, // Recent
        // People & world
        ["person.fill"]       = 0xE77B, // Contact
        ["person.2.fill"]     = 0xE716, // People
        ["globe"]             = 0xE774, // Globe
        // App chrome / actions
        ["tray.full.fill"]    = 0xE8F1, // Library
        ["tray"]              = 0xE8F1, // Library
        ["folder.badge.plus"] = 0xE8F4, // NewFolder
        ["doc.on.clipboard.fill"] = 0xE77F, // Paste
        ["doc.on.doc"]        = 0xE8C8, // Copy
        ["pin"]               = 0xE718, // Pin
        ["pin.fill"]          = 0xE842, // Pinned
        ["pin.slash"]         = 0xE77A, // Unpin
        ["safari"]            = 0xE774, // Globe
        ["trash"]             = 0xE74D, // Delete
        ["pencil"]            = 0xE70F, // Edit
        ["plus.square.on.square"] = 0xE8C8, // Copy
        ["macwindow"]         = 0xE7B9, // Tiles
        ["power"]             = 0xE7E8, // PowerButton
        ["magnifyingglass"]   = 0xE721, // Search
        ["plus"]              = 0xE710, // Add
        ["minus.magnifyingglass"] = 0xE71F, // ZoomOut
        ["plus.magnifyingglass"]  = 0xE8A3, // ZoomIn
        ["rectangle.grid.1x2"]    = 0xE8FD, // BulletedList
        ["checkmark.circle.fill"] = 0xEC61, // CompletedSolid
        ["xmark.circle.fill"]     = 0xE711, // Cancel
        ["chevron.right"]     = 0xE76C, // ChevronRight
        ["sparkle"]           = 0xE706, // Brightness
    };

    /// <summary>The curated icon set offered in the category editor.</summary>
    public static readonly string[] CategoryOptions =
    {
        "textformat", "paragraph", "square.and.pencil", "note.text",
        "text.alignleft", "text.cursor", "signature", "character",
        "curlybraces", "terminal.fill", "function", "command", "keyboard",
        "list.bullet", "list.number", "checklist", "list.clipboard",
        "doc.text.fill", "text.quote", "number",
        "link", "at", "bubble.left.fill", "megaphone.fill", "envelope.fill",
        "wand.and.stars", "sparkles", "arrow.triangle.2.circlepath",
        "paintpalette.fill", "camera.fill", "music.note",
        "tag.fill", "bookmark.fill", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "calendar", "clock",
        "person.fill", "person.2.fill", "globe",
    };

    public static string Glyph(string symbolName)
        => char.ConvertFromUtf32(_map.TryGetValue(symbolName, out var cp) ? cp : Fallback);
}
