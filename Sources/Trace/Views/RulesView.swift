import SwiftUI
import TraceCore

/// Every automatic rule in matching order, and the activity no rule caught.
struct RulesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hits: [Int64: Int] = [:]
    @State private var loose: [LooseItem] = []
    @State private var showsForm = false

    var body: some View {
        let order = Dictionary(uniqueKeysWithValues: model.tags.enumerated().map { ($0.element.id ?? 0, $0.offset) })
        let rules = model.rules.sorted { (order[$0.tagID] ?? 0, $0.id ?? 0) < (order[$1.tagID] ?? 0, $1.id ?? 0) }
        Page {
            PageHeader(title: L("Rules"),
                       subtitle: L("Matching activity is tagged automatically; rules are checked from top to bottom")) {
                Button(L("New rule")) { showsForm = true }.buttonStyle(.trProminent)
            }
            if showsForm || model.ruleDraft != nil {
                NewRuleForm { showsForm = false; model.ruleDraft = nil }
            }
            HStack(alignment: .top, spacing: 12) {
                Card(padding: .hv(20, 6)) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rules) { rule in
                            RuleRow(rule: rule, tag: model.tags.first { $0.id == rule.tagID }, hits: hits[rule.id ?? 0] ?? 0)
                            Hairline()
                        }
                        Text(L("Activity that matches no rule stays untagged. You can tag single records by hand in the timeline."))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .padding(.vertical, 12)
                    }
                }
                Card(padding: .hv(20, 18)) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(title: L("Untagged activity"))
                        Text(looseNote).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                        ForEach(loose.prefix(6)) { item in
                            Hairline()
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.label).fontWeight(.semibold).lineLimit(1)
                                    Text(Fmt.duration(item.seconds)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Button(L("Create rule")) { model.ruleDraft = (item.field, item.value) }
                                    .buttonStyle(TRButtonStyle(kind: .bordered, height: 28))
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .frame(width: 320)
            }
        }
        .task(id: model.revision) { load() }
    }

    private var looseNote: String {
        let total = loose.reduce(0) { $0 + $1.seconds }
        return total > 0 ? String(format: L("%@ this week has no tag yet"), Fmt.duration(total))
                         : L("Everything this week has a tag")
    }

    private func load() {
        let week = model.weekInterval
        let events = model.events(in: week)
        var counts: [Int64: Int] = [:]
        for rule in model.rules {
            guard let id = rule.id else { continue }
            counts[id] = events.reduce(0) { $0 + (rule.matches($1) ? 1 : 0) }
        }
        hits = counts
        loose = Analyzer.untagged(events, in: week, tagger: model.tagger)
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var model: AppModel
    let rule: Rule
    let tag: Tag?
    let hits: Int
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(rule.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(rule.op.displayName).foregroundStyle(Theme.muted)
            Text(rule.shortValue).font(Theme.mono).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                .layoutPriority(1)
                .help(rule.value)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            TagChip(tag: tag)
            Spacer(minLength: 8)
            Text(String(format: L("%d matches this week"), hits)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize()
            Button { model.deleteRule(rule) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help(L("Delete rule"))
            .accessibilityLabel(L("Delete rule"))
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let tag {
                Button(String(format: L("Raise priority of “%@”"), tag.displayName)) { model.moveTag(tag, by: -1) }
                Button(String(format: L("Lower priority of “%@”"), tag.displayName)) { model.moveTag(tag, by: 1) }
                Divider()
            }
            Button(L("Delete rule"), role: .destructive) { model.deleteRule(rule) }
        }
    }
}

private struct NewRuleForm: View {
    @EnvironmentObject private var model: AppModel
    let done: () -> Void
    @State private var field: RuleField = .app
    @State private var op: RuleOp = .contains
    @State private var value = ""
    @State private var tagID: Int64?

    var body: some View {
        Card(padding: .hv(20, 14)) {
            HStack(spacing: 10) {
                Text(L("When")).foregroundStyle(Theme.muted)
                RuleFields(field: $field, op: $op, value: $value, onSubmit: save)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                Picker(L("Tag"), selection: $tagID) {
                    ForEach(model.tags) { tag in Text(tag.displayName).tag(tag.id) }
                }
                .labelsHidden()
                .fixedSize()
                Button(L("Save"), action: save)
                    .buttonStyle(TRButtonStyle(kind: .prominent, height: 32))
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty || tagID == nil)
                Button(L("Cancel"), action: done).buttonStyle(TRButtonStyle(kind: .bordered, height: 32))
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: model.ruleDraft?.value) { prefill() }
    }

    private func prefill() {
        if tagID == nil { tagID = model.tags.first?.id }
        if let draft = model.ruleDraft {
            field = draft.field
            op = draft.field == .app ? .equals : .contains
            value = draft.value
        }
    }

    private func save() {
        guard let tag = model.tags.first(where: { $0.id == tagID }),
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.addRule(to: tag, field: field, op: op, value: value)
        value = ""
        done()
    }
}
