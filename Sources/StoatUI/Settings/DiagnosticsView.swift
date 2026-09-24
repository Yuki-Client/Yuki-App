import SwiftUI
import UIKit
import StoatCore

struct DiagnosticsView: View {
    @State private var log = DiagnosticsLog.shared
    @State private var filter: DiagnosticsLog.Category?
    @State private var copied = false

    private var entries: [DiagnosticsLog.Entry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.category == filter }
    }

    var body: some View {
        List {
            Section {
                Text(log.deviceSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = log.export()
                    copied = true
                    YukiHaptics.notification(.success)
                } label: {
                    Label(copied ? "Copied" : "Copy Everything", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                ShareLink(item: log.export()) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Holds the last \(log.entries.count) events. No message text, names or email addresses are included.")
            }

            if entries.isEmpty {
                Section {
                    Text("Nothing recorded yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: entry.category.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(entry.category == .error ? Color.red : YukiTheme.accent)
                                Text(entry.category.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                Button("Clear", role: .destructive) {
                    log.clear()
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        filter = nil
                    } label: {
                        Label("Everything", systemImage: filter == nil ? "checkmark" : "line.3.horizontal.decrease")
                    }
                    ForEach(DiagnosticsLog.Category.allCases, id: \.self) { category in
                        Button {
                            filter = category
                        } label: {
                            Label(category.rawValue, systemImage: filter == category ? "checkmark" : category.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
        }
        .onChange(of: log.entries.count) { _, _ in
            copied = false
        }
    }
}
