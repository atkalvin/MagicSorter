import SwiftUI
import UniformTypeIdentifiers

// --- EXTENSIONS & MODÈLES ---

// Pour sauvegarder la langue dans les préférences TEST -
enum AppLanguage: String, Codable, CaseIterable {
    case english = "en"
    case french = "fr"
    
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .french: return "🇫🇷"
        }
    }
}

// Structure pour l'historique (Undo)
struct MovedFile: Identifiable {
    let id = UUID()
    let originalURL: URL
    let destinationURL: URL
}

enum FileCategory: String, CaseIterable, Identifiable {
    case images, videos, music, documents, archives, apps, code, other
    
    var id: String { self.rawValue }
    
    func label(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .images: return "Images"
            case .videos: return "Videos"
            case .music: return "Music"
            case .documents: return "Documents"
            case .archives: return "Archives"
            case .apps: return "Apps"
            case .code: return "Code"
            case .other: return "Other"
            }
        case .french:
            switch self {
            case .images: return "Images"
            case .videos: return "Vidéos"
            case .music: return "Musique"
            case .documents: return "Documents"
            case .archives: return "Archives"
            case .apps: return "Apps"
            case .code: return "Code"
            case .other: return "Autres"
            }
        }
    }
    
    var icon: String {
        switch self {
        case .images: return "photo.stack"
        case .videos: return "film.stack"
        case .music: return "music.note.list"
        case .documents: return "doc.text.fill"
        case .archives: return "archivebox.fill"
        case .apps: return "app.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "folder.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .images: return .pink
        case .videos: return .orange
        case .music: return .purple
        case .documents: return .blue
        case .archives: return .brown
        case .apps: return .green
        case .code: return .gray
        case .other: return .secondary
        }
    }
    
    static func category(for extensionName: String) -> FileCategory {
        let ext = extensionName.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "svg", "tiff", "bmp", "webp", "raw": return .images
        case "mp4", "mov", "mkv", "avi", "webm", "m4v": return .videos
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma": return .music
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "pages", "numbers", "key", "md", "rtf": return .documents
        case "zip", "rar", "7z", "tar", "gz", "dmg", "iso": return .archives
        case "app", "exe", "pkg": return .apps
        case "swift", "py", "js", "html", "css", "c", "cpp", "json", "java", "php", "ts": return .code
        default: return .other
        }
    }
}

// --- VUE PRINCIPALE ---

struct ContentView: View {
    // --- PERSISTENCE (@AppStorage) ---
    @AppStorage("language") private var currentLanguage: AppLanguage = .english
    @AppStorage("createParentFolder") private var createParentFolder: Bool = true
    @AppStorage("parentFolderName") private var parentFolderName: String = ""
    @AppStorage("isRecursive") private var isRecursive: Bool = false
    @AppStorage("isSimulation") private var isSimulation: Bool = false
    // Stockage simple des catégories désactivées (liste séparée par des virgules)
    @AppStorage("disabledCategories") private var disabledCategoriesString: String = ""
    
    // --- ÉTATS LOCAUX ---
    @State private var selectedFolderURL: URL?
    @State private var isProcessing: Bool = false
    @State private var isDragging: Bool = false // Pour l'effet visuel du drag & drop
    
    // Gestion Undo
    @State private var undoStack: [[MovedFile]] = []
    
    // Logs
    @State private var logs: [LogEntry] = []
    struct LogEntry: Identifiable {
        let id = UUID()
        let message: String
        let type: LogType
    }
    enum LogType { case info, success, warning, dryRun }
    
    // Grid Layout
    let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 15)]
    
    var body: some View {
        ZStack {
            // Fond principal
            VStack(spacing: 0) {
                headerView
                Divider()
                mainScrollView
                Divider()
                consoleAndActionsView
            }
            
            // Overlay visuel lors du Drag & Drop
            if isDragging {
                Color.blue.opacity(0.1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
                            .foregroundColor(.blue)
                            .padding()
                    )
                    .overlay(
                        VStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                            Text(currentLanguage == .english ? "Drop folder here" : "Déposez le dossier ici")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    )
                    .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            }
        }
        .frame(minWidth: 700, minHeight: 800)
        // Gestion du Drag & Drop
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let data = data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    // Vérifier si c'est bien un dossier
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        DispatchQueue.main.async {
                            self.selectedFolderURL = url
                            self.addLog(currentLanguage == .english ? "Folder loaded via drag & drop" : "Dossier chargé via glisser-déposer", type: .success)
                        }
                    }
                }
            }
            return true
        }
    }
    
    // --- SOUS-VUES ---
    
    var headerView: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 50, height: 50)
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.white)
                    .font(.title2)
            }
            
            VStack(alignment: .leading) {
                Text("Magic Sorter Pro")
                    .font(.title2.bold())
                Text(currentLanguage == .english ? "Ultimate File Organizer" : "L'organisateur ultime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: toggleLanguage) {
                Text(currentLanguage.flag)
                    .font(.title2)
                    .padding(5)
            }
            .buttonStyle(.plain)
            
            HStack {
                if let url = selectedFolderURL {
                    VStack(alignment: .trailing) {
                        Text(currentLanguage == .english ? "Target:" : "Cible :")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(url.lastPathComponent).fontWeight(.medium)
                    }
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text(currentLanguage == .english ? "Drag a folder here" : "Glissez un dossier ici")
                        .foregroundStyle(.secondary)
                }
                
                Button(currentLanguage == .english ? "Choose..." : "Choisir...") { selectFolder() }
                    .buttonStyle(.bordered)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        }
        .padding()
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }
    
    var mainScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                
                // Options Avancées
                GroupBox(label: Label("Options", systemImage: "slider.horizontal.3").font(.headline)) {
                    VStack(alignment: .leading, spacing: 15) {
                        
                        // Rangée 1 : Dossier Parent & Récursivité
                        HStack(spacing: 30) {
                            Toggle(isOn: $createParentFolder) {
                                Text(currentLanguage == .english ? "Create parent folder" : "Créer un dossier parent")
                            }
                            .toggleStyle(.switch)
                            
                            Toggle(isOn: $isRecursive) {
                                HStack {
                                    Text(currentLanguage == .english ? "Scan subfolders" : "Scanner sous-dossiers")
                                    Image(systemName: "arrow.triangle.branch").font(.caption)
                                }
                            }
                            .toggleStyle(.switch)
                            .help(currentLanguage == .english ? "Look inside folders in the source directory" : "Regarde à l'intérieur des dossiers existants")
                        }
                        
                        if createParentFolder {
                            HStack {
                                Text(currentLanguage == .english ? "Folder Name:" : "Nom du dossier :")
                                TextField("", text: $parentFolderName, prompt: Text("Auto"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 250)
                            }
                        }
                        
                        Divider()
                        
                        // Rangée 2 : Mode Simulation
                        Toggle(isOn: $isSimulation) {
                            HStack {
                                Image(systemName: "eye.fill")
                                VStack(alignment: .leading) {
                                    Text(currentLanguage == .english ? "Simulation Mode (Dry Run)" : "Mode Simulation")
                                        .fontWeight(.semibold)
                                    Text(currentLanguage == .english ? "See what happens without moving files" : "Voir les actions sans déplacer les fichiers")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(8)
                        .background(isSimulation ? Color.orange.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .padding(10)
                }
                
                // Grille de Catégories
                VStack(alignment: .leading) {
                    HStack {
                        Label(currentLanguage == .english ? "File Types" : "Types de fichiers", systemImage: "square.grid.2x2")
                            .font(.headline)
                        Spacer()
                    }
                    
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(FileCategory.allCases) { category in
                            CategoryCard(
                                category: category,
                                language: currentLanguage,
                                isSelected: Binding(
                                    get: { !isDisabled(category) },
                                    set: { newValue in setDisabled(category, disabled: !newValue) }
                                )
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    var consoleAndActionsView: some View {
        VStack(spacing: 0) {
            // Logs
            List(logs) { log in
                HStack(alignment: .top) {
                    Image(systemName: logIcon(for: log.type))
                        .foregroundStyle(logColor(for: log.type))
                    Text(log.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(log.type == .dryRun ? .orange : .primary)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.plain)
            .frame(height: 150)
            .background(Color.black.opacity(0.85))
            
            // Actions Bar
            HStack {
                // Bouton UNDO
                if !undoStack.isEmpty {
                    Button(action: undoLastBatch) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text(currentLanguage == .english ? "Undo Last" : "Annuler")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
                
                if isProcessing {
                    ProgressView().controlSize(.small)
                }
                
                // Bouton Principal
                Button(action: startSorting) {
                    HStack {
                        if isSimulation {
                            Image(systemName: "eye")
                            Text(currentLanguage == .english ? "Simulate Sort" : "Simuler")
                        } else {
                            Image(systemName: "play.fill")
                            Text(currentLanguage == .english ? "Sort Files" : "Trier")
                        }
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSimulation ? .orange : .blue)
                .disabled(selectedFolderURL == nil || isProcessing)
            }
            .padding()
            .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
        }
    }
    
    // --- LOGIQUE UI & HELPERS ---
    
    func toggleLanguage() {
        withAnimation {
            currentLanguage = (currentLanguage == .english) ? .french : .english
            if parentFolderName.isEmpty || parentFolderName.starts(with: "Sorted") || parentFolderName.starts(with: "Trié") {
                let dateStr = Date().formatted(date: .numeric, time: .omitted)
                parentFolderName = currentLanguage == .english ? "Sorted \(dateStr)" : "Trié le \(dateStr)"
            }
        }
    }
    
    func isDisabled(_ cat: FileCategory) -> Bool {
        disabledCategoriesString.contains(cat.rawValue)
    }
    
    func setDisabled(_ cat: FileCategory, disabled: Bool) {
        var items = disabledCategoriesString.split(separator: ",").map(String.init)
        if disabled {
            if !items.contains(cat.rawValue) { items.append(cat.rawValue) }
        } else {
            items.removeAll { $0 == cat.rawValue }
        }
        disabledCategoriesString = items.joined(separator: ",")
    }
    
    func logIcon(for type: LogType) -> String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .dryRun: return "eye"
        }
    }
    
    func logColor(for type: LogType) -> Color {
        switch type {
        case .info: return .gray
        case .success: return .green
        case .warning: return .yellow
        case .dryRun: return .orange
        }
    }
    
    func addLog(_ message: String, type: LogType = .info) {
        DispatchQueue.main.async {
            if self.logs.count > 150 { self.logs.removeFirst() }
            self.logs.append(LogEntry(message: message, type: type))
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = currentLanguage == .english ? "Choose folder" : "Choisir un dossier"
        if panel.runModal() == .OK {
            selectedFolderURL = panel.url
            logs.removeAll()
            addLog("Dossier : \(panel.url?.path ?? "")")
        }
    }
    
    // --- LOGIQUE MÉTIER PRINCIPALE ---
    
    func startSorting() {
        guard let sourceURL = selectedFolderURL else { return }
        
        isProcessing = true
        logs.removeAll()
        
        let simMode = isSimulation
        let recursive = isRecursive
        let lang = currentLanguage
        let folderName = parentFolderName
        let createParent = createParentFolder
        let disabledRaw = disabledCategoriesString
        
        addLog(simMode ? (lang == .english ? "--- SIMULATION STARTED ---" : "--- SIMULATION DÉMARRÉE ---") : (lang == .english ? "--- SORTING STARTED ---" : "--- TRI DÉMARRÉ ---"), type: simMode ? .dryRun : .info)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var batchMoves: [MovedFile] = []
            var filesCount = 0
            
            // Logique de récupération des fichiers (Recursive ou Flat)
            var fileURLs: [URL] = []
            
            if recursive {
                if let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let fileURL as URL in enumerator {
                        if !fileURL.hasDirectoryPath {
                            fileURLs.append(fileURL)
                        }
                    }
                }
            } else {
                do {
                    fileURLs = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
                    fileURLs = fileURLs.filter { !$0.hasDirectoryPath }
                } catch {
                    addLog("Error reading directory", type: .warning)
                }
            }
            
            // Filtrage basique
            let filesToProcess = fileURLs.filter { url in
                !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != ".DS_Store"
            }
            
            if filesToProcess.isEmpty {
                addLog(lang == .english ? "No files found." : "Aucun fichier trouvé.", type: .warning)
                DispatchQueue.main.async { isProcessing = false }
                return
            }
            
            // Définition de la racine de destination
            var rootDestination = sourceURL
            if createParent {
                let defaultName = lang == .english ? "Sorted" : "Trié"
                let safeName = folderName.isEmpty ? defaultName : folderName
                rootDestination = sourceURL.appendingPathComponent(safeName)
                
                if !simMode && !fileManager.fileExists(atPath: rootDestination.path) {
                    try? fileManager.createDirectory(at: rootDestination, withIntermediateDirectories: true)
                }
            }
            
            // BOUCLE DE TRI
            for fileURL in filesToProcess {
                let ext = fileURL.pathExtension
                let category = FileCategory.category(for: ext)
                
                // Vérifier si désactivé
                if disabledRaw.contains(category.rawValue) {
                    continue
                }
                
                // Vérifier qu'on ne déplace pas des fichiers déjà dans le dossier de destination (si récursif)
                if fileURL.path.contains(rootDestination.path) {
                    continue
                }
                
                let categoryName = category.label(language: lang)
                let categoryFolder = rootDestination.appendingPathComponent(categoryName)
                
                if !simMode && !fileManager.fileExists(atPath: categoryFolder.path) {
                    try? fileManager.createDirectory(at: categoryFolder, withIntermediateDirectories: true)
                }
                
                // Calcul nom unique
                var finalURL = categoryFolder.appendingPathComponent(fileURL.lastPathComponent)
                var counter = 1
                while fileManager.fileExists(atPath: finalURL.path) && finalURL != fileURL {
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    finalURL = categoryFolder.appendingPathComponent("\(name) \(counter).\(ext)")
                    counter += 1
                }
                
                // Action
                if simMode {
                    addLog("Would move: \(fileURL.lastPathComponent) -> \(categoryName)", type: .dryRun)
                } else {
                    do {
                        try fileManager.moveItem(at: fileURL, to: finalURL)
                        batchMoves.append(MovedFile(originalURL: fileURL, destinationURL: finalURL))
                        filesCount += 1
                        addLog("Moved: \(fileURL.lastPathComponent)", type: .success)
                    } catch {
                        addLog("Error moving \(fileURL.lastPathComponent): \(error.localizedDescription)", type: .warning)
                    }
                }
                
                // Petit délai pour l'UI
                if filesCount < 50 { Thread.sleep(forTimeInterval: 0.01) }
            }
            
            DispatchQueue.main.async {
                isProcessing = false
                if !simMode && !batchMoves.isEmpty {
                    self.undoStack.append(batchMoves)
                    NSSound(named: "Glass")?.play()
                }
                addLog(lang == .english ? "Finished." : "Terminé.", type: simMode ? .dryRun : .success)
            }
        }
    }
    
    // --- LOGIQUE UNDO ---
    
    func undoLastBatch() {
        guard let lastBatch = undoStack.popLast() else { return }
        
        isProcessing = true
        addLog(currentLanguage == .english ? "Undoing last operation..." : "Annulation en cours...", type: .info)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var recoveredCount = 0
            
            // On inverse l'ordre pour éviter les conflits
            for move in lastBatch.reversed() {
                do {
                    if fileManager.fileExists(atPath: move.destinationURL.path) {
                        // S'assurer que le dossier d'origine existe encore
                        let originalDir = move.originalURL.deletingLastPathComponent()
                        if !fileManager.fileExists(atPath: originalDir.path) {
                            try fileManager.createDirectory(at: originalDir, withIntermediateDirectories: true)
                        }
                        
                        try fileManager.moveItem(at: move.destinationURL, to: move.originalURL)
                        recoveredCount += 1
                    }
                } catch {
                    print("Undo error: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.addLog("Undo complete: \(recoveredCount) files restored.", type: .success)
            }
        }
    }
}

// --- VISUAL ELEMENTS ---

struct CategoryCard: View {
    let category: FileCategory
    let language: AppLanguage
    @Binding var isSelected: Bool
    
    var body: some View {
        Button(action: { withAnimation(.spring()) { isSelected.toggle() } }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? category.color.gradient : Color.gray.opacity(0.15).gradient)
                        .frame(width: 45, height: 45)
                    Image(systemName: category.icon)
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                Text(category.label(language: language))
                    .font(.headline)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? category.color : Color.clear, lineWidth: 2))
            .opacity(isSelected ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

#Preview {
    ContentView()
}
