// Games Bridgeplay starts without Steam, see GamesModel

import SwiftUI

struct GamesView: View {

    @Environment(GamesModel.self) private var model
    @State private var addingGame = false
    @State private var gameSettings: WinePrefix?

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.hasLoaded {
                ProgressView("Looking for games")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.games.isEmpty {
                ContentUnavailableView {
                    Label("No Games", systemImage: "gamecontroller")
                } description: {
                    Text("Add a Windows game that is not from Steam. Bridgeplay gives it its own prefix and starts it without Steam.")
                } actions: {
                    Button("New Game…") { addingGame = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .navigationTitle("Games")
        .safeAreaInset(edge: .bottom) {
            if let failed = model.report {
                report(
                    StatusRow(
                        title: String(localized: "Failed"),
                        value: failed.message,
                        tone: .bad,
                        action: failed.settingsPane.map { pane in
                            StatusAction(label: Remedy.settingsButton) { Remedy.openSettings(pane) }
                        },
                        menu: ErrorReport.actions(failed.message, in: "Games")
                    )
                )
            } else if let outcome = model.outcome {
                report(StatusRow(title: String(localized: "Done"), value: outcome, tone: .ok))
            }
        }
        .toolbar {
            if #available(macOS 26.1, *) {
                ToolbarItemGroup(placement: .primaryAction) { strip }
                    .visibilityPriority(.high)
            } else {
                ToolbarItemGroup(placement: .primaryAction) { strip }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $addingGame) {
            NewGameSheet(tools: model.tools) { name, tool in
                Task {
                    if let game = await model.add(name: name, tool: tool) { model.chooseInstaller(for: game) }
                }
            }
        }
        .sheet(item: $gameSettings) { prefix in
            GameSettingsView(prefix: prefix)
        }
        .confirmationDialog(
            String(localized: "Remove \(model.removing?.name ?? "")?"),
            isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }),
            titleVisibility: .visible,
            presenting: model.removing
        ) { game in
            Button("Remove Game", role: .destructive) {
                Task { await model.removeGame(game) }
            }
            Button("Cancel", role: .cancel) { model.removing = nil }
                .keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("This deletes the game's prefix, with anything installed or saved in it. A game folder outside the prefix, such as one in Downloads, is kept. Back up the prefix in Prefixes first to keep it.")
        }
        .confirmationDialog(
            String(localized: "Force quit \(model.quitting?.name ?? "")?"),
            isPresented: Binding(get: { model.quitting != nil }, set: { if !$0 { model.quitting = nil } }),
            titleVisibility: .visible,
            presenting: model.quitting
        ) { game in
            Button("Force Quit", role: .destructive) {
                Task { await model.forceQuit(game) }
            }
            Button("Cancel", role: .cancel) { model.quitting = nil }
                .keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("Every program in the game's prefix is stopped at once, including its launcher. Progress the game has not saved is lost.")
        }
    }

    @ViewBuilder
    private var strip: some View {
        let game = model.selectedGame

        Button("New Game…", systemImage: "plus") { addingGame = true }
            .help("Add a Windows game that is not from Steam.")

        Button("Run Installer…", systemImage: "square.and.arrow.down") {
            if let game { model.chooseInstaller(for: game) }
        }
        .disabled(game == nil)
        .help("Run the selected game's installer in its own prefix.")

        Button("Choose Program…", systemImage: "app.badge.checkmark") {
            if let game { Task { await model.chooseProgram(for: game) } }
        }
        .disabled(game == nil)
        .help("Choose the program Play starts, such as the game's launcher, inside its prefix or in a folder of its own.")

        Button("Game Settings", systemImage: "slider.horizontal.3") {
            if let game { gameSettings = GameStore.prefix(of: game) }
        }
        .disabled(game == nil)
        .help("Choose the graphics, frame generation and other settings the selected game runs with.")

        Button("Play", systemImage: "play.fill") {
            if let game { model.play(game) }
        }
        .disabled(game.map { model.program($0) == nil } ?? true)
        .help("Start the selected game.")

        Button("Force Quit", systemImage: "xmark.octagon") {
            model.quitting = game
        }
        .disabled(game == nil || model.isLoading)
        .help("Stop the selected game when it hangs and will not close.")

        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await model.load() }
        }
        .disabled(model.isLoading)
        .help("List the games again.")
    }

    private var table: some View {
        @Bindable var model = model
        return Table(model.games, selection: $model.selection) {
            TableColumn("Game") { game in
                Text(game.name).help(game.name)
            }
            .width(min: 80, ideal: 220)

            TableColumn("Program") { game in
                if let program = model.program(game) {
                    Text(program).help(game.executable ?? program)
                } else {
                    (model.hasPrefix(game) ? Text("Not chosen") : Text("Not installed")).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 180)

            TableColumn("Compatibility Tool") { game in
                Text(model.toolName(game) ?? String(localized: "Automatic")).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 160)

            TableColumn("ID") { game in
                Text(game.id).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 100)
        }
        .contextMenu(forSelectionType: StandaloneGame.ID.self) { ids in
            if let game = model.games.first(where: { ids.contains($0.id) }) {
                actions(for: game)
            }
        } primaryAction: { ids in
            if let game = model.games.first(where: { ids.contains($0.id) }), model.program(game) != nil {
                model.play(game)
            }
        }
        .onDeleteCommand {
            model.removing = model.selectedGame
        }
    }

    @ViewBuilder
    private func actions(for game: StandaloneGame) -> some View {
        Button("Play") { model.play(game) }
            .disabled(model.program(game) == nil)
        Button("Run Installer…") { model.chooseInstaller(for: game) }
        Button("Choose Program…") { Task { await model.chooseProgram(for: game) } }
        Button("Game Settings") { gameSettings = GameStore.prefix(of: game) }
        Menu("Compatibility Tool") {
            Picker("Compatibility Tool", selection: Binding(
                get: { game.tool },
                set: { tool in Task { await model.setTool(tool, for: game) } }
            )) {
                Text("Automatic").tag(String?.none)
                ForEach(model.tools) { tool in
                    Text(tool.display).tag(Optional(tool.name))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Divider()
        Button("Force Quit…") { model.quitting = game }
        Button("Reveal in Finder") { PrefixTools.reveal(GameStore.prefix(of: game)) }
        Divider()
        Button("Remove Game…", role: .destructive) { model.removing = game }
    }

    private func report(_ row: StatusRow) -> some View {
        row.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }
}

private struct NewGameSheet: View {
    let tools: [InstalledTool]
    let add: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tool: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Game")
                .font(.headline)
            Text("Name the game, then choose its installer. Bridgeplay runs the installer in the game's own prefix, without Steam.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Name", text: $name)
                Picker("Compatibility Tool", selection: $tool) {
                    Text("Automatic").tag(String?.none)
                    ForEach(tools) { tool in
                        Text(tool.display).tag(Optional(tool.name))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add and Choose Installer…") {
                    add(name, tool)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
