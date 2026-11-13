import Foundation

/// Applies tags to events. Rules decide automatically; changes made by hand
/// on a single event override them. Tags are ordered by `sortOrder`, and the
/// first one is the event's primary tag, the one charts are coloured by. A
/// tag added by hand always comes before the automatic ones.
public struct Tagger: Sendable {
    public let tags: [Tag]
    private let rulesByTag: [Int64: [Rule]]
    private let added: [Int64: Set<Int64>]
    private let removed: [Int64: Set<Int64>]

    public init(tags: [Tag], rules: [Rule], manual: [ManualTag] = []) {
        self.tags = tags.filter(\.enabled).sorted { ($0.sortOrder, $0.id ?? 0) < ($1.sortOrder, $1.id ?? 0) }
        rulesByTag = Dictionary(grouping: rules, by: \.tagID)
        var added: [Int64: Set<Int64>] = [:], removed: [Int64: Set<Int64>] = [:]
        for m in manual {
            if m.removed { removed[m.eventID, default: []].insert(m.tagID) }
            else { added[m.eventID, default: []].insert(m.tagID) }
        }
        self.added = added
        self.removed = removed
    }

    private func matches(_ tag: Tag, _ event: ActivityEvent) -> Bool {
        guard let id = tag.id, let rules = rulesByTag[id] else { return false }
        return rules.contains { $0.matches(event) }
    }

    /// Tags the rules alone would apply.
    public func automatic(for event: ActivityEvent) -> [Tag] {
        tags.filter { matches($0, event) }
    }

    public func tags(for event: ActivityEvent) -> [Tag] {
        guard let id = event.id, added[id] != nil || removed[id] != nil else { return automatic(for: event) }
        let add = added[id] ?? [], rem = removed[id] ?? []
        let manual = tags.filter { $0.id.map(add.contains) ?? false }
        let auto = automatic(for: event).filter { tag in
            guard let tagID = tag.id else { return false }
            return !rem.contains(tagID) && !add.contains(tagID)
        }
        return manual + auto
    }

    public func primary(for event: ActivityEvent) -> Tag? {
        if let id = event.id, added[id] != nil || removed[id] != nil { return tags(for: event).first }
        return tags.first { matches($0, event) }
    }

    /// Whether `tag` is on `event` because the user put it there.
    public func isManual(_ tag: Tag, for event: ActivityEvent) -> Bool {
        guard let id = event.id, let tagID = tag.id else { return false }
        return added[id]?.contains(tagID) ?? false
    }
}

/// Built-in tags, seeded on first launch. They rely on the category each app
/// declares in its Info.plist (`LSApplicationCategoryType`) plus a short list of
/// well-known apps and sites, so they work without any setup.
public enum Presets {
    public struct Preset: Sendable {
        public let key: String
        public let name: String
        public let colorIndex: Int
        public let rules: [(RuleField, RuleOp, String)]
    }

    /// Order matters: site rules come before the catch-all "browsing" tag.
    public static let all: [Preset] = [
        Preset(key: "dev", name: "Development", colorIndex: 0, rules: [
            (.category, .equals, "public.app-category.developer-tools"),
            (.app, .equals, "com.apple.Terminal"),
            (.app, .equals, "com.googlecode.iterm2"),
            (.app, .equals, "com.microsoft.VSCode"),
            (.app, .equals, "dev.zed.Zed"),
            (.url, .contains, "github.com"),
            (.url, .contains, "stackoverflow.com"),
        ]),
        Preset(key: "study", name: "Study", colorIndex: 1, rules: [
            (.category, .equals, "public.app-category.education"),
            (.category, .equals, "public.app-category.reference"),
            (.url, .contains, "developer.apple.com"),
            (.url, .contains, "wikipedia.org"),
        ]),
        Preset(key: "comm", name: "Communication", colorIndex: 2, rules: [
            (.category, .equals, "public.app-category.social-networking"),
            (.app, .equals, "com.apple.mail"),
            (.app, .equals, "com.apple.MobileSMS"),
            (.app, .equals, "com.tinyspeck.slackmacgap"),
            (.app, .equals, "com.tencent.xinWeChat"),
            (.app, .equals, "us.zoom.xos"),
            (.app, .equals, "com.microsoft.teams2"),
            (.app, .equals, "com.electron.lark"),
        ]),
        Preset(key: "fun", name: "Entertainment", colorIndex: 4, rules: [
            (.category, .equals, "public.app-category.entertainment"),
            (.category, .equals, "public.app-category.music"),
            (.category, .equals, "public.app-category.video"),
            (.url, .contains, "youtube.com"),
            (.url, .contains, "bilibili.com"),
            (.url, .contains, "netflix.com"),
        ]),
        Preset(key: "games", name: "Games", colorIndex: 6, rules: [
            (.category, .contains, "games"),
            (.app, .equals, "com.valvesoftware.steam"),
            (.app, .equals, "com.epicgames.EpicGamesLauncher"),
        ]),
        Preset(key: "design", name: "Design", colorIndex: 7, rules: [
            (.category, .equals, "public.app-category.graphics-design"),
            (.category, .equals, "public.app-category.photography"),
            (.app, .equals, "com.figma.Desktop"),
            (.app, .equals, "com.bohemiancoding.sketch3"),
        ]),
        Preset(key: "office", name: "Office", colorIndex: 5, rules: [
            (.category, .equals, "public.app-category.productivity"),
            (.category, .equals, "public.app-category.business"),
            (.category, .equals, "public.app-category.finance"),
            (.app, .equals, "com.apple.iWork.Pages"),
            (.app, .equals, "com.apple.iWork.Keynote"),
            (.app, .equals, "com.apple.iWork.Numbers"),
            (.app, .equals, "com.microsoft.Word"),
            (.app, .equals, "com.microsoft.Excel"),
            (.app, .equals, "com.microsoft.Powerpoint"),
            (.app, .equals, "com.kingsoft.wpsoffice.mac"),
        ]),
        Preset(key: "browse", name: "Browsing", colorIndex: 3, rules: [
            (.app, .equals, "com.apple.Safari"),
            (.app, .equals, "com.google.Chrome"),
            (.app, .equals, "company.thebrowser.Browser"),
            (.app, .equals, "org.mozilla.firefox"),
            (.app, .equals, "com.microsoft.edgemac"),
            (.app, .equals, "com.brave.Browser"),
        ]),
    ]
}
