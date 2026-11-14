import Foundation

/// Applies tags to events. Rules decide automatically; a session started by
/// hand claims everything that happens while it runs; and changes made on a
/// single event override both. The first tag is the event's primary tag,
/// the one charts are coloured by: a tag added by hand, else the session's
/// tag, else the first matching rule in `sortOrder`.
public struct Tagger: Sendable {
    public let tags: [Tag]
    private let rulesByTag: [Int64: [Rule]]
    private let added: [Int64: Set<Int64>]
    private let removed: [Int64: Set<Int64>]
    /// Sessions per device, sorted by start.
    private let sessions: [String: [FocusSession]]

    public init(tags: [Tag], rules: [Rule], manual: [ManualTag] = [], sessions: [FocusSession] = []) {
        self.sessions = Dictionary(grouping: sessions, by: \.device).mapValues { $0.sorted { $0.start < $1.start } }
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

    /// The tag of the session an event falls in, if any.
    public func sessionTag(for event: ActivityEvent) -> Tag? {
        guard let list = sessions[event.device], !list.isEmpty else { return nil }
        // The last session that started at or before the event.
        var low = 0, high = list.count
        while low < high {
            let mid = (low + high) / 2
            if list[mid].start <= event.start { low = mid + 1 } else { high = mid }
        }
        guard low > 0, list[low - 1].contains(event.start, device: event.device) else { return nil }
        let tagID = list[low - 1].tagID
        return tags.first { $0.id == tagID }
    }

    public func tags(for event: ActivityEvent) -> [Tag] {
        let session = sessionTag(for: event)
        let overridden = event.id.map { added[$0] != nil || removed[$0] != nil } ?? false
        guard session != nil || overridden else { return automatic(for: event) }
        let add = event.id.flatMap { added[$0] } ?? [], rem = event.id.flatMap { removed[$0] } ?? []
        var result = tags.filter { $0.id.map(add.contains) ?? false }
        for tag in [session].compactMap({ $0 }) + automatic(for: event) {
            guard let tagID = tag.id, !rem.contains(tagID), !result.contains(where: { $0.id == tagID }) else { continue }
            result.append(tag)
        }
        return result
    }

    public func primary(for event: ActivityEvent) -> Tag? {
        let overridden = event.id.map { added[$0] != nil || removed[$0] != nil } ?? false
        if overridden || !sessions.isEmpty, sessions[event.device] != nil || overridden {
            return tags(for: event).first
        }
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
        /// Rules added in a later version; existing databases receive them
        /// once, so a rule the user has deleted does not come back.
        public var added: [(RuleField, RuleOp, String)] = []
    }

    /// Raised whenever `added` grows.
    public static let version = 2

    private static func apps(_ ids: String...) -> [(RuleField, RuleOp, String)] { ids.map { (.app, .equals, $0) } }
    private static func sites(_ hosts: String...) -> [(RuleField, RuleOp, String)] { hosts.map { (.url, .contains, $0) } }

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
        ],
               added: apps("com.todesktop.230313mzl4w4u92", "com.sublimetext.4", "com.github.GitHubClient", "dev.warp.Warp-Stable",
                         "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.docker.docker", "com.postmanlabs.mac",
                         "com.tinyapp.TablePlus", "com.navicat.NavicatPremium", "com.termius-dmg.mac", "org.gnu.Emacs",
                         "com.google.android.studio", "com.mongodb.compass", "com.apple.Console")
                + [(.app, .hasPrefix, "com.jetbrains.")]
                + sites("gitlab.com", "gitee.com", "huggingface.co", "npmjs.com", "pypi.org", "juejin.cn", "csdn.net",
                        "leetcode", "docs.rs", "pkg.go.dev", "localhost", "127.0.0.1")),
        Preset(key: "study", name: "Study", colorIndex: 1, rules: [
            (.category, .equals, "public.app-category.education"),
            (.category, .equals, "public.app-category.reference"),
            (.url, .contains, "developer.apple.com"),
            (.url, .contains, "wikipedia.org"),
        ],
               added: apps("org.zotero.zotero", "com.apple.iBooksX", "net.ankiweb.dtop", "com.readdle.PDFExpert-Mac",
                         "com.apple.Dictionary", "texstudio", "edu.bibdesk")
                + sites("arxiv.org", "scholar.google", "overleaf.com", "coursera.org", "cnki.net", "semanticscholar.org",
                        "dl.acm.org", "ieeexplore.ieee.org", "sciencedirect.com", "springer.com", "openreview.net",
                        "nature.com", "researchgate.net", "docs.python.org", "edx.org", "khanacademy.org")),
        Preset(key: "comm", name: "Communication", colorIndex: 2, rules: [
            (.category, .equals, "public.app-category.social-networking"),
            (.app, .equals, "com.apple.mail"),
            (.app, .equals, "com.apple.MobileSMS"),
            (.app, .equals, "com.tinyspeck.slackmacgap"),
            (.app, .equals, "com.tencent.xinWeChat"),
            (.app, .equals, "us.zoom.xos"),
            (.app, .equals, "com.microsoft.teams2"),
            (.app, .equals, "com.electron.lark"),
        ],
               added: apps("com.tencent.qq", "com.tencent.WeWorkMac", "com.alibaba.DingTalkMac", "com.bytedance.macos.feishu",
                         "com.tencent.meeting", "com.microsoft.Outlook", "com.apple.FaceTime", "ru.keepcoder.Telegram",
                         "net.whatsapp.WhatsApp", "com.hnc.Discord", "com.netease.macmail", "com.skype.skype",
                         "com.readdle.smartemail-Mac", "com.apple.mobilephone")
                + sites("mail.google.com", "outlook.live.com", "outlook.office.com", "mail.qq.com", "mail.163.com",
                        "slack.com", "discord.com", "web.whatsapp.com", "web.telegram.org", "meet.google.com",
                        "feishu.cn", "larksuite.com", "teams.microsoft.com")),
        Preset(key: "fun", name: "Entertainment", colorIndex: 4, rules: [
            (.category, .equals, "public.app-category.entertainment"),
            (.category, .equals, "public.app-category.music"),
            (.category, .equals, "public.app-category.video"),
            (.url, .contains, "youtube.com"),
            (.url, .contains, "bilibili.com"),
            (.url, .contains, "netflix.com"),
        ],
               added: apps("com.netease.163music", "com.tencent.QQMusicMac", "com.spotify.client", "com.apple.Music", "com.apple.TV",
                         "com.colliderli.iina", "org.videolan.vlc", "com.apple.podcasts", "com.apple.QuickTimePlayerX")
                + sites("douyin.com", "twitch.tv", "weibo.com", "twitter.com", "//x.com", "reddit.com", "instagram.com",
                        "tiktok.com", "iqiyi.com", "v.qq.com", "youku.com", "music.163.com", "xiaohongshu.com",
                        "douban.com", "spotify.com", "facebook.com", "zhihu.com", "disneyplus.com", "primevideo.com")),
        Preset(key: "games", name: "Games", colorIndex: 6, rules: [
            (.category, .contains, "games"),
            (.app, .equals, "com.valvesoftware.steam"),
            (.app, .equals, "com.epicgames.EpicGamesLauncher"),
        ],
               added: apps("net.battle.app", "com.mojang.minecraftlauncher", "com.riotgames.RiotGames.RiotClientUx",
                         "com.apple.Chess", "com.gog.galaxy")
                + sites("store.steampowered.com", "steamcommunity.com", "epicgames.com", "itch.io")),
        Preset(key: "design", name: "Design", colorIndex: 7, rules: [
            (.category, .equals, "public.app-category.graphics-design"),
            (.category, .equals, "public.app-category.photography"),
            (.app, .equals, "com.figma.Desktop"),
            (.app, .equals, "com.bohemiancoding.sketch3"),
        ],
               added: apps("com.adobe.Photoshop", "com.adobe.illustrator", "com.adobe.InDesign", "com.adobe.PremierePro",
                         "com.adobe.AfterEffects", "com.pixelmatorteam.pixelmator.x", "com.seriflabs.affinitydesigner2",
                         "com.seriflabs.affinityphoto2", "com.apple.FinalCut", "com.blackmagic-design.DaVinciResolve",
                         "com.jgraph.drawio.desktop", "com.apple.freeform")
                + sites("figma.com", "canva.com", "dribbble.com", "behance.net")),
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
        ],
               added: apps("com.apple.Notes", "notion.id", "md.obsidian", "com.apple.reminders", "com.apple.iCal",
                         "com.lukilabs.lukiapp", "com.adobe.Acrobat.Pro", "com.microsoft.onenote.mac", "com.apple.Preview",
                         "com.evernote.Evernote", "com.culturedcode.ThingsMac", "com.todoist.mac.Todoist")
                + sites("docs.google.com", "sheets.google.com", "notion.so", "yuque.com", "shimo.im", "docs.qq.com",
                        "office.com", "calendar.google.com", "drive.google.com", "trello.com", "airtable.com")),
        Preset(key: "browse", name: "Browsing", colorIndex: 3, rules: [
            (.app, .equals, "com.apple.Safari"),
            (.app, .equals, "com.google.Chrome"),
            (.app, .equals, "company.thebrowser.Browser"),
            (.app, .equals, "org.mozilla.firefox"),
            (.app, .equals, "com.microsoft.edgemac"),
            (.app, .equals, "com.brave.Browser"),
        ],
               added: apps("com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.kagi.kagimacOS",
                         "app.zen-browser.zen", "com.duckduckgo.macos.browser", "com.google.Chrome.canary")),
    ]
}
