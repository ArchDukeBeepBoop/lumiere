import SwiftUI
import LumiereKit

/// The rules of one smart collection, as Apple Music's smart playlist editor
/// lays them out: Match all or any, then a row per rule — field, operator,
/// value — with + and −, and underneath what the rules match right now.
struct SmartRuleEditor: View {
    @Binding var name: String
    @Binding var rules: SmartRules
    let choices: SmartChoices?
    let preview: SmartPreview?

    /// Field names in the order a person thinks of them, and their labels.
    static let fields: [(id: String, label: String)] = [
        ("genre", "Genre"), ("keyword", "Keyword"), ("country", "Country"), ("studio", "Studio"),
        ("library", "Library"), ("type", "Kind"), ("year", "Year"), ("rating", "Rating"),
        ("runtime", "Length (minutes)"), ("added", "Added"), ("watched", "Watched"),
        ("favourite", "Favourite"), ("name", "Title"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).font(Theme.Font.body)
            HStack(spacing: Theme.Space.xs) {
                Text("Match")
                Picker("", selection: $rules.match) {
                    Text("all").tag("all")
                    Text("any").tag("any")
                }
                .labelsHidden().fixedSize()
                Text("of these rules")
                Spacer()
                Picker("Order", selection: Binding(get: { rules.sort ?? "rating" }, set: { rules.sort = $0 })) {
                    Text("Best rated").tag("rating")
                    Text("Newest").tag("year")
                    Text("Recently added").tag("added")
                    Text("Title").tag("name")
                }
                .fixedSize()
            }
            .font(Theme.Font.body)
            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach($rules.rules) { $rule in
                        row($rule)
                    }
                }
            }
            .frame(maxHeight: 230)
            Divider()
            previewView
        }
    }

    private func row(_ rule: Binding<SmartRule>) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Picker("", selection: rule.field) {
                ForEach(Self.fields, id: \.id) { Text($0.label).tag($0.id) }
            }
            .labelsHidden().frame(width: 150)
            .onChange(of: rule.wrappedValue.field) {
                rule.wrappedValue.op = operators(rule.wrappedValue.field).first ?? "is"
                rule.wrappedValue.value = defaultValue(rule.wrappedValue.field)
            }
            Picker("", selection: rule.op) {
                ForEach(operators(rule.wrappedValue.field), id: \.self) { Text(label(op: $0)).tag($0) }
            }
            .labelsHidden().frame(width: 110)
            valueField(rule)
            Button { rules.rules.removeAll { $0.id == rule.wrappedValue.id } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).disabled(rules.rules.count == 1).labelledHelp("Remove this rule")
            Button { rules.rules.append(SmartRule(field: "genre", op: "is", value: "")) } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless).labelledHelp("Add a rule")
        }
    }

    @ViewBuilder
    private func valueField(_ rule: Binding<SmartRule>) -> some View {
        let field = rule.wrappedValue.field
        let options = valueOptions(field)
        if !options.isEmpty {
            Picker("", selection: rule.value) {
                Text("Choose…").tag("")
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden()
        } else {
            TextField(placeholder(field), text: rule.value).textFieldStyle(.roundedBorder)
        }
    }

    private var previewView: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            if let preview {
                Text(preview.count == 0 ? "Nothing matches these rules yet." : "\(preview.count) titles match")
                    .font(Theme.Font.body.weight(.semibold))
                if let names = preview.names, !names.isEmpty {
                    Text(names.joined(separator: " · "))
                        .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(3)
                }
            } else {
                Text("Fill in every rule to see what it matches.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func operators(_ field: String) -> [String] {
        choices?.fields[field] ?? ["is"]
    }

    private func label(op: String) -> String {
        ["is": "is", "is not": "is not", "≥": "at least", "≤": "at most", "within days": "within the last", "contains": "contains"][op] ?? op
    }

    private func placeholder(_ field: String) -> String {
        ["year": "1990", "rating": "8", "runtime": "90", "added": "days, e.g. 30", "name": "words in the title"][field] ?? ""
    }

    private func defaultValue(_ field: String) -> String {
        ["watched": "false", "favourite": "true", "type": "Movie"][field] ?? ""
    }

    private func valueOptions(_ field: String) -> [(value: String, label: String)] {
        let list: (([String]?) -> [(value: String, label: String)]) = { ($0 ?? []).map { ($0, $0) } }
        switch field {
        case "genre": return list(choices?.genres)
        case "keyword": return list(choices?.keywords)
        case "studio": return list(choices?.studios)
        case "country":
            return (choices?.countries ?? []).map { ($0, LibraryRepository.countryName($0)) }
                .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
        case "library": return (choices?.libraries ?? []).map { ($0.id, $0.name) }
        case "type": return [("Movie", "Film"), ("Series", "Show")]
        case "watched": return [("false", "No"), ("true", "Yes")]
        case "favourite": return [("true", "Yes"), ("false", "No")]
        default: return []
        }
    }
}
