import SwiftUI
import LumiereKit

/// Smart collections: collections made of rules, which the server keeps
/// current — "Korean crime", "unwatched films under 90 minutes", "added this
/// month". Three panes, as Apple Music's smart playlists and Kometa's builders
/// suggest: ideas worked out from this library, the ones you have, and the
/// editor with a live count of what the rules match.
struct SmartCollectionsSheet: View {
    let client: JellyfinClient
    let onDone: (_ changed: Bool) -> Void

    enum Pane: String, CaseIterable, Identifiable {
        case ideas = "Ideas", yours = "Yours", edit = "Edit"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .ideas
    @State private var ideas: [SmartIdea] = []
    @State private var yours: [SmartCollectionSummary] = []
    @State private var choices: SmartChoices?
    @State private var editingId: String?
    @State private var name = ""
    @State private var rules = SmartRules(rules: [SmartRule(field: "genre", op: "is", value: "")])
    @State private var preview: SmartPreview?
    @State private var message: String?
    @State private var changed = false
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Smart Collections").font(Theme.Font.title)
                Spacer()
                Picker("", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            Text("Collections made of rules. The server keeps them current: a title that comes to fit joins by itself, one that stops fitting leaves.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            switch pane {
            case .ideas: ideasPane
            case .yours: yoursPane
            case .edit:
                SmartRuleEditor(name: $name, rules: $rules, choices: choices, preview: preview)
                    .task(id: rules) { await refreshPreview() }
            }
            if let message {
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.danger)
            }
            HStack {
                Spacer()
                Button("Done") { onDone(changed) }.keyboardShortcut(.cancelAction)
                if pane == .edit {
                    Button(editingId == nil ? "Create" : "Save") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || (preview?.count ?? 0) == 0)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 680, height: 600)
        .glassSheet()
        .task { await load() }
    }

    private var ideasPane: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Theme.Space.sm)], spacing: Theme.Space.sm) {
                ForEach(ideas) { idea in
                    Button { edit(name: idea.name, rules: idea.rules, id: nil) } label: {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(idea.name).font(Theme.Font.body.weight(.semibold))
                                .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                            Text("\(idea.count) titles").font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(Theme.Space.sm)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .labelledHelp("Start from \(idea.name)")
                }
            }
            if ideas.isEmpty {
                Text("Ideas appear as the library's genres, countries and years fill in.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var yoursPane: some View {
        List {
            Button { edit(name: "", rules: SmartRules(rules: [SmartRule(field: "genre", op: "is", value: "")]), id: nil) } label: {
                Label("New Smart Collection", systemImage: "plus.circle.fill")
            }
            ForEach(yours) { smart in
                Button { edit(name: smart.name, rules: smart.rules, id: smart.id) } label: {
                    HStack {
                        Image(systemName: "gearshape.2").foregroundStyle(Theme.Palette.accent)
                        Text(smart.name)
                        Spacer()
                        Text("\(smart.count)").foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func edit(name: String, rules: SmartRules, id: String?) {
        self.name = name
        self.rules = rules
        editingId = id
        pane = .edit
    }

    private func load() async {
        async let i = client.smartIdeas()
        async let y = client.smartCollections()
        async let c = client.smartChoices()
        ideas = (try? await i) ?? []
        yours = ((try? await y) ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        choices = try? await c
    }

    private func refreshPreview() async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, rules.rules.allSatisfy({ !$0.value.isEmpty }) else { preview = nil; return }
        preview = try? await client.previewSmart(rules)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await client.saveSmartCollection(id: editingId, name: name, rules: rules)
            editingId = saved.id
            changed = true
            message = nil
            await load()
            pane = .yours
        } catch {
            message = ConnectionState.message(for: error)
        }
    }
}
