import AppKit
import SwiftUI

/// The engine the menu bar shows, set before it starts.
var menuBarEngine: Engine!

/// Shows cueback's menu bar icon and panel for as long as the process runs.
func runMenuBar(_ engine: Engine) -> Never {
    menuBarEngine = engine
    CuebackBar.main()
    exit(0)
}

struct CuebackBar: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)   // a menu bar icon, no Dock icon
        menuBarEngine.attachUI()
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(engine: menuBarEngine)
        } label: {
            BarIcon(engine: menuBarEngine)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct BarIcon: View {
    @ObservedObject var engine: Engine

    var body: some View {
        Image(systemName: !engine.isOn ? "bell.slash" : engine.config.isQuiet() ? "moon.zzz" : "bell")
    }
}

private struct CueButton: Identifiable {
    let id: String
    let title: String
}

private let tryableCues = [
    CueButton(id: "permission", title: "Permission"), CueButton(id: "waiting", title: "Waiting"),
    CueButton(id: "input", title: "Input"), CueButton(id: "done", title: "Done"),
    CueButton(id: "error", title: "Error"), CueButton(id: "installed", title: "Installed"),
    CueButton(id: "subagent-start", title: "Subagent start"), CueButton(id: "subagent-stop", title: "Subagent stop"),
]

private struct Panel: View {
    @ObservedObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            volumeSection
            Divider()
            quietSection
            Divider()
            cueSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { engine.refresh() }
    }

    private var stateColor: Color {
        !engine.isOn ? .secondary : engine.config.isQuiet() ? .purple : .green
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("cueback").font(.system(size: 14, weight: .semibold))
                Text(engine.statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Cues", isOn: Binding(get: { engine.isOn }, set: { engine.setOn($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Volume")
                Spacer()
                Text("\(Int(engine.volume))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $engine.volume, in: 0...100, step: 5, onEditingChanged: { editing in
                    if !editing { engine.commitVolume() }
                })
                Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var quietSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Quiet hours")
                Spacer()
                Toggle("Quiet hours", isOn: Binding(get: { engine.config.quietHours },
                                                    set: { on in engine.updateConfig { $0.quietHours = on } }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            HStack(spacing: 8) {
                DatePicker("From", selection: time(\.quietStart), displayedComponents: .hourAndMinute)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                DatePicker("To", selection: time(\.quietEnd), displayedComponents: .hourAndMinute)
                Spacer()
            }
            .labelsHidden()
            .datePickerStyle(.field)
            .disabled(!engine.config.quietHours)
            Text("Cues from Claude Code stay silent; the ones you try here still play.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var cueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Try a cue")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(tryableCues) { cue in
                    Button { engine.preview(cue.id) } label: { Text(cue.title).frame(maxWidth: .infinity) }
                        .controlSize(.small)
                }
            }
            Button { engine.playDemo() } label: {
                Label(engine.demoPlaying ? "Playing the demo…" : "Play the demo", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.demoPlaying)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(engine.lastCueLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Log") { engine.openLog() }.buttonStyle(.link).font(.caption)
            Button("Quit") { engine.quit() }.buttonStyle(.link).font(.caption)
        }
    }

    private func time(_ key: WritableKeyPath<Config, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(engine.config[keyPath: key]) * 60) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                engine.updateConfig { $0[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
            })
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }
}

extension Engine {
    var statusLine: String {
        if !isOn { return "Off · Claude Code's cues are silent" }
        if config.isQuiet() { return "Quiet hours until " + String(format: "%02d:%02d", config.quietEnd / 60, config.quietEnd % 60) }
        return "On · listening to Claude Code"
    }

    var lastCueLine: String {
        guard let lastCue else { return "No cues yet" }
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        return "Last: \(lastCue.name) · \(clock.string(from: lastCue.at))"
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/cueback.log"))
    }

    /// Stops cueback until the next login (it runs as a LaunchAgent, which would otherwise start it again).
    func quit() {
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["bootout", "gui/\(getuid())/app.cueback.daemon"]
        try? launchctl.run()
        launchctl.waitUntilExit()
        exit(0)
    }
}
