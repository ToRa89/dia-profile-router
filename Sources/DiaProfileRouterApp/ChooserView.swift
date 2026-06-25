// Sources/DiaProfileRouterApp/ChooserView.swift
import SwiftUI
import DiaRouterCore
import DiaRouterShell

struct ChooserView: View {
    let url: URL
    let profiles: [Profile]
    let defaultDirectory: String
    /// Called exactly once: a ChooserResult on choose, nil on cancel.
    let onDecision: (ChooserResult?) -> Void

    @State private var remember = false
    @State private var pattern: String

    init(url: URL, profiles: [Profile], defaultDirectory: String,
         onDecision: @escaping (ChooserResult?) -> Void) {
        self.url = url
        self.profiles = profiles
        self.defaultDirectory = defaultDirectory
        self.onDecision = onDecision
        _pattern = State(initialValue: RuleSuggestion.hostPattern(for: url) ?? (url.host ?? ""))
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link öffnen in welchem Profil?").font(.headline)
            Text(url.absoluteString)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(profiles) { profile in
                    Button { choose(profile.directory) } label: {
                        Text(profile.name).frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .modifier(DefaultActionIf(isDefault: profile.directory == defaultDirectory))
                }
            }

            Toggle("Immer diesen Host als Regel merken", isOn: $remember)
            if remember {
                TextField("Host", text: $pattern).textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { onDecision(nil) }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func choose(_ directory: String) {
        let pat = (remember && !pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            ? pattern.trimmingCharacters(in: .whitespaces) : nil
        onDecision(ChooserResult(profileDirectory: directory, rememberPattern: pat))
    }
}

/// Makes the default-profile button respond to Return.
private struct DefaultActionIf: ViewModifier {
    let isDefault: Bool
    func body(content: Content) -> some View {
        if isDefault { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
