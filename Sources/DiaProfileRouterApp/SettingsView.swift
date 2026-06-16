// Sources/DiaProfileRouterApp/SettingsView.swift
import SwiftUI
import DiaRouterCore

struct SettingsView: View {
    @StateObject private var vm = ConfigViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dia Profile Router").font(.headline)
                Spacer()
                if vm.isDefaultBrowser {
                    Label("Standardbrowser", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Button("Als Standardbrowser setzen") { vm.setAsDefaultBrowser() }
                }
            }

            Divider()

            HStack {
                Text("Default-Profil")
                Picker("", selection: $vm.config.defaultProfileDirectory) {
                    ForEach(vm.profiles) { p in Text(p.name).tag(p.directory) }
                }.labelsHidden().onChange(of: vm.config.defaultProfileDirectory) { _ in vm.save() }
            }

            Divider()
            Text("Regeln (erste passende gewinnt)").font(.subheadline).foregroundStyle(.secondary)

            List {
                ForEach($vm.config.rules) { $rule in
                    HStack(spacing: 8) {
                        Picker("", selection: $rule.matchType) {
                            ForEach(MatchType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 90)
                        TextField("Muster", text: $rule.pattern).onSubmit { vm.save() }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Picker("", selection: $rule.profileDirectory) {
                            ForEach(vm.profiles) { p in Text(p.name).tag(p.directory) }
                        }.labelsHidden().frame(width: 140)
                        Button(role: .destructive) { vm.deleteRule(rule) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in vm.config.rules.move(fromOffsets: from, toOffset: to); vm.save() }
            }
            .frame(minHeight: 200)
            .onChange(of: vm.config.rules) { _ in vm.save() }

            HStack {
                Button("Regel hinzufügen") { vm.addRule() }
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 560)
        .onAppear { vm.reload() }
    }
}
