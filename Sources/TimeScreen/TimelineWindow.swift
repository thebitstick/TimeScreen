import ImageIO
import SwiftUI

private let cellWidth: CGFloat = 176
private let cellHeight: CGFloat = 110
private let cellSpacing: CGFloat = 10

struct TimelineWindow: View {
    @ObservedObject var recorder: Recorder
    let bridge: ScrubBridge
    let onClose: () -> Void

    @State private var days: [Date] = []
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var loadedFrames: [Frame] = []
    @State private var display = 0
    @State private var appFilter: String?
    @State private var searchApp: String?
    @State private var searchRange = SearchRange.anyTime
    @State private var allApps: [(app: String, count: Int)] = []
    @State private var selectedID: Int64?
    @State private var pendingFrameID: Int64?
    @State private var pendingDisplay: Int?
    @State private var scrollRequest: ScrollRequest?
    @State private var image: NSImage?
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var boxes: [WordBox] = []
    @State private var showCalendar = false
    @State private var jumpText = ""
    @State private var jumpFailed = false
    @State private var selection: CGRect?
    @State private var statusMessage: String?
    @State private var deleteRequest: DeleteRequest?
    @State private var excludeRequest: ExcludeRequest?
    @State private var didChooseInitialDay = false
    @State private var zoom = PreviewZoom()
    @State private var showRecap = false
    @AppStorage("textPanelMode") private var panelMode = "text"
    @ObservedObject private var summarizer = Summarizer.shared
    @State private var showStarred = false
    @State private var starredFrames: [Frame] = []
    @State private var previewSize = CGSize(width: 1, height: 1)
    @State private var pointer = PointerTracker()
    @State private var panStart: CGSize?
    @State private var pinchStart: PinchStart?
    @State private var fullText = ""
    @State private var boxesID: Int64?
    @AppStorage("showTextPanel") private var showText = false
    @FocusState private var searchFocused: Bool
    @FocusState private var focused: Bool

    private var displays: [Int] { Set(loadedFrames.map(\.display)).sorted() }
    private var dayFrames: [Frame] { displays.count > 1 ? loadedFrames.filter { $0.display == display } : loadedFrames }
    private var frames: [Frame] { appFilter.map { app in dayFrames.filter { $0.app == app } } ?? dayFrames }
    private var appCounts: [(app: String, count: Int)] {
        Dictionary(grouping: dayFrames, by: \.app).map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }
    private var currentIndex: Int? { frames.firstIndex { $0.id == selectedID } }
    private var current: Frame? { currentIndex.map { frames[$0] } }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var highlights: [WordBox] {
        WordBox.matches(boxes, terms: SearchQuery(query).highlightTerms)
    }

    private var isTypingInTextField: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    private var selectedWords: [WordBox] {
        guard let selection else { return [] }
        return boxes.filter { $0.rect.intersects(selection) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                if isSearching {
                    resultsList
                    Divider()
                }
                preview
                if showText {
                    Divider()
                    textPanel
                }
            }
            info
            ActivityBar(frames: dayFrames, selectedID: selectedID, filter: appFilter) { select($0, animated: false) }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            filmstrip
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard !isTypingInTextField else { return .ignored }
            let direction = press.key == .rightArrow ? 1 : -1
            if press.modifiers.contains(.command) {
                jumpToEnd(first: direction < 0)
            } else if press.modifiers.contains(.option) {
                jumpToAppSwitch(direction)
            } else {
                step(press.modifiers.contains(.shift) ? direction * 10 : direction)
            }
            return .handled
        }
        .onKeyPress(.home) {
            guard !isTypingInTextField else { return .ignored }
            jumpToEnd(first: true)
            return .handled
        }
        .onKeyPress(.end) {
            guard !isTypingInTextField else { return .ignored }
            jumpToEnd(first: false)
            return .handled
        }
        .onKeyPress(characters: ["f"], phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            searchFocused = true
            return .handled
        }
        .onKeyPress(characters: ["/"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.isEmpty else { return .ignored }
            searchFocused = true
            return .handled
        }
        .onKeyPress(characters: ["=", "+"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            zoom.zoom(by: 1.5, around: pointer.location, in: previewSize)
            return .handled
        }
        .onKeyPress(characters: ["-"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            zoom.zoom(by: 1 / 1.5, around: pointer.location, in: previewSize)
            return .handled
        }
        .onKeyPress(characters: ["0"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.contains(.command) else { return .ignored }
            zoom.reset()
            pointer.location = nil
            return .handled
        }
        .onKeyPress(characters: ["s"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.isEmpty else { return .ignored }
            toggleStar()
            return .handled
        }
        .onKeyPress(characters: ["t"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers.isEmpty else { return .ignored }
            showText.toggle()
            return .handled
        }
        .onKeyPress(characters: ["c"], phases: .down) { press in
            guard !isTypingInTextField else { return .ignored }
            guard press.modifiers == .command else { return .ignored }
            copyText()
            return .handled
        }
        .onChange(of: selectedID) { selection = nil }
        .onAppear {
            focused = true
            applyLaunchOptions()
        }
        .task { await reloadDays() }
        .task(id: day) { await loadDay() }
        .task(id: SearchKey(query: query, app: searchApp, range: searchRange, day: day)) { await runSearch() }
        .onChange(of: appFilter) { keepSelectionVisible() }
        .task(id: selectedID) { await loadImage() }
        .task(id: selectedID) { await loadBoxes() }
        .confirmationDialog(deleteRequest?.title ?? "", isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } }),
                            titleVisibility: .visible, presenting: deleteRequest) { request in
            Button("Delete \(request.frames.count) \(request.frames.count == 1 ? "Frame" : "Frames")", role: .destructive) {
                Task { await performDelete(request) }
            }
        } message: { request in
            let starred = request.frames.filter(\.starred).count
            Text("The screenshots and their search text are removed. This can't be undone."
                 + (starred > 0 ? " \(starred) of them \(starred == 1 ? "is" : "are") starred, and starred screenshots go too." : ""))
        }
        .confirmationDialog("Never record \(excludeRequest?.app ?? "")?",
                            isPresented: Binding(get: { excludeRequest != nil }, set: { if !$0 { excludeRequest = nil } }),
                            titleVisibility: .visible, presenting: excludeRequest) { request in
            if let bundleID = request.bundleID {
                Button("Never Record \(request.app)") {
                    Prefs.excludeApp(bundleID)
                    flash("\(request.app) won't be recorded")
                }
                if !request.frames.isEmpty {
                    Button("Never Record and Delete \(request.frames.count) \(request.frames.count == 1 ? "Frame" : "Frames")", role: .destructive) {
                        Prefs.excludeApp(bundleID)
                        Task { await performDelete(DeleteRequest(title: "", frames: request.frames)) }
                    }
                }
            }
        } message: { request in
            if request.bundleID != nil {
                Text("While \(request.app) is the topmost window, nothing is captured. Screenshots already taken stay unless you delete them. You can undo this in Settings → Privacy.")
            } else {
                Text("TimeScreen couldn't identify \(request.app). Add its bundle identifier under Settings → Privacy → Never capture.")
            }
        }
        .onChange(of: recorder.revision) {
            Task {
                await reloadDays()
                if Calendar.current.isDateInToday(day) { await refreshFrames() }
            }
        }
    }


    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { showCalendar.toggle() } label: {
                    Label(day.formatted(.dateTime.weekday(.wide).month().day()), systemImage: "calendar")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                    CalendarPopover(days: days, day: $day) { showCalendar = false }
                }

                if displays.count > 1 { displayMenu }
                appMenu
                jumpField
                starredButton
                recapButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search everything you've seen", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .help("Words match from the start. Use \"quotes\" for an exact phrase and a minus sign to leave a word out.")
                    .onKeyPress(.downArrow) { moveResult(1) }
                    .onKeyPress(.upArrow) { moveResult(-1) }
                    .onSubmit {
                        if !hits.isEmpty, !hits.contains(where: { $0.frame.id == selectedID }) { jump(to: hits[0].frame) }
                        focused = true
                    }
                if isSearching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 420)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Close (esc)")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34) // clears the fullscreen menu bar reveal area
        .padding(.bottom, 10)
    }

    private var displayMenu: some View {
        Picker("Display", selection: $display) {
            ForEach(displays, id: \.self) { Text(Self.displayName($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .onChange(of: display) { keepSelectionVisible() }
    }

    static func displayName(_ index: Int) -> String { index == 0 ? "Main Display" : "Display \(index + 1)" }

    private var recapButton: some View {
        Button { showRecap.toggle() } label: { Image(systemName: "sparkles") }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("A recap of this day, written on this Mac")
            .popover(isPresented: $showRecap, arrowEdge: .bottom) {
                DayRecapView(day: day, db: recorder.db, summarizer: summarizer)
            }
    }

    private var starredButton: some View {
        Button {
            Task {
                starredFrames = (try? await recorder.db.starredFrames()) ?? []
                showStarred = true
            }
        } label: { Image(systemName: "star") }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Starred screenshots")
        .popover(isPresented: $showStarred, arrowEdge: .bottom) {
            if starredFrames.isEmpty {
                Text("Star a screenshot (S) to keep it forever.\nStarred ones are never deleted by retention or the size limit.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(20)
            } else {
                List(starredFrames) { frame in
                    Button {
                        showStarred = false
                        jump(to: frame)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(frame.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            Text(frame.title.isEmpty ? frame.app : "\(frame.app) — \(frame.title)").lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 340, height: min(CGFloat(starredFrames.count) * 52 + 16, 360))
            }
        }
    }

    private func toggleStar() {
        guard let frame = current, let i = loadedFrames.firstIndex(where: { $0.id == frame.id }) else { return }
        let starred = !frame.starred
        loadedFrames[i].starred = starred
        Task {
            try? await recorder.db.setStarred(starred, id: frame.id)
            flash(starred ? "Starred: kept forever" : "Unstarred")
        }
    }

    private var jumpField: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").foregroundStyle(.secondary)
            TextField("Jump to time", text: $jumpText)
                .textFieldStyle(.plain)
                .frame(width: 96)
                .onSubmit(jump)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red, lineWidth: jumpFailed ? 1.5 : 0))
        .help("Type a time such as 3:45pm, 15:30 or noon, then press Return")
    }

    private func jump() {
        let visible = frames
        let target = JumpTime.candidates(jumpText, on: day)
            .compactMap { date in Activity.nearest(visible, to: date.timeIntervalSince1970).map { (visible[$0], abs(visible[$0].date.timeIntervalSince(date))) } }
            .min { $0.1 < $1.1 }
        guard let frame = target?.0 else {
            jumpFailed = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                jumpFailed = false
            }
            return
        }
        select(frame.id, animated: true)
        jumpText = ""
    }

    private var appMenu: some View {
        Menu {
            Button { appFilter = nil } label: {
                Label("All Apps", systemImage: appFilter == nil ? "checkmark" : "square.grid.2x2")
            }
            Divider()
            ForEach(appCounts, id: \.app) { entry in
                Button { appFilter = entry.app } label: {
                    if let icon = AppIcons.shared.icon(for: entry.app) {
                        Image(nsImage: icon)
                    }
                    Text("\(entry.app)  (\(entry.count))")
                }
            }
        } label: {
            if let appFilter, let icon = AppIcons.shared.icon(for: appFilter) {
                HStack(spacing: 6) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    Text(appFilter)
                }
            } else {
                Label(appFilter ?? "All Apps", systemImage: "square.grid.2x2")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var preview: some View {
        ZStack {
            if let image {
                ZStack {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .overlay { highlightOverlay }
                        .overlay { selectionOverlay }
                        .scaleEffect(zoom.scale)
                        .offset(zoom.offset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .overlay(alignment: .topLeading) {
                    if zoom.isZoomed {
                        Button { zoom.reset(); pointer.location = nil } label: { Text("\(Int((zoom.scale * 100).rounded()))%  ✕").monospacedDigit() }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(10)
                            .help("Reset the zoom (⌘0). Drag to select text; hold ⇧ and drag to move.")
                    }
                }
                .padding(.horizontal, 20)
            } else if frames.isEmpty {
                Text(recorder.isRecording ? "Nothing captured on this day yet" : "Recording is paused")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Boxes drawn over the matched words. Vision's origin is bottom-left, so y is flipped.
    private var highlightOverlay: some View {
        GeometryReader { geometry in
            ForEach(Array(highlights.enumerated()), id: \.offset) { _, box in
                let width = CGFloat(box.w) * geometry.size.width + 8
                let height = CGFloat(box.h) * geometry.size.height + 4
                RoundedRectangle(cornerRadius: 3)
                    .fill(.yellow.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.yellow, lineWidth: 1.5))
                    .frame(width: width, height: height)
                    .position(x: CGFloat(box.x + box.w / 2) * geometry.size.width,
                              y: CGFloat(1 - box.y - box.h / 2) * geometry.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var selectionOverlay: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(selectedWords.enumerated()), id: \.offset) { _, word in
                    let r = word.rect
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: r.width * size.width + 4, height: r.height * size.height + 2)
                        .position(x: r.midX * size.width, y: r.midY * size.height)
                }
                if let selection {
                    Rectangle().stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                        .frame(width: selection.width * size.width, height: selection.height * size.height)
                        .offset(x: selection.minX * size.width, y: selection.minY * size.height)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer.location = location
                case .ended: pointer.location = nil
                }
            }
            .onAppear { previewSize = size }
            .onChange(of: size) { previewSize = size }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !panning else { return }
                let a = value.startLocation, b = value.location
                let rect = CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                                  width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)
                selection = hypot(a.x - b.x, a.y - b.y) < 3 ? nil : rect
            })
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                guard panning else { return }
                let start = panStart ?? zoom.offset
                panStart = start
                zoom.pan(to: CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height), in: size)
            }.onEnded { _ in
                panStart = nil
                pointer.location = nil
            })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                let start = pinchStart ?? PinchStart(zoom: zoom, anchor: CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height))
                pinchStart = start
                zoom.pinch(to: start.zoom.scale * value.magnification, around: start.anchor, from: start.zoom, in: size)
            }.onEnded { _ in pinchStart = nil })
        }
    }

    private var panning: Bool { zoom.isZoomed && NSEvent.modifierFlags.contains(.shift) }

    private func copyText() {
        guard boxesID == selectedID else { return }
        let words = selectedWords
        let text = selection == nil ? frameText : WordBox.text(of: words)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = selection == nil ? "Copied all text" : "Copied \(words.count) \(words.count == 1 ? "word" : "words")"
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            statusMessage = nil
        }
    }

    private var exportMenu: some View {
        Menu {
            if let frame = current {
                Button("Save Image…") { Exporter.saveImage(of: frame, root: recorder.framesRoot, window: TimelineController.shared.overlayWindow, done: flash) }
                Button("Copy Image") { flash(Exporter.copyImage(of: frame, root: recorder.framesRoot)) }
                Button("Save Text…") {
                    Task {
                        let text = (try? await recorder.db.texts(for: [frame.id]))?[frame.id] ?? ""
                        Exporter.saveText(of: frame, text: text, window: TimelineController.shared.overlayWindow, done: flash)
                    }
                }
                Button("Show File in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recorder.framesRoot.appendingPathComponent(frame.path)]) }
                Divider()
            }
            Button("Export This Day…") { exportDay() }
            if isSearching, !hits.isEmpty {
                Button("Export Search Results…") { exportSearchResults() }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Save or export screenshots and their text")
    }

    private func exportDay() {
        let frames = loadedFrames
        guard !frames.isEmpty else { flash("Nothing to export"); return }
        let title = "TimeScreen " + day.formatted(.iso8601.year().month().day())
        Task {
            let texts = (try? await recorder.db.texts(for: frames.map(\.id))) ?? [:]
            Exporter.exportDay(frames: frames, texts: texts, title: title, root: recorder.framesRoot,
                               window: TimelineController.shared.overlayWindow, done: flash)
        }
    }

    private func exportSearchResults() {
        let frames = hits.map(\.frame)
        let title = "TimeScreen search \(query.trimmingCharacters(in: .whitespaces))"
        Task {
            let texts = (try? await recorder.db.texts(for: frames.map(\.id))) ?? [:]
            Exporter.saveTranscript(frames: frames, texts: texts, title: title,
                                    window: TimelineController.shared.overlayWindow, done: flash)
        }
    }

    private var deleteMenu: some View {
        Menu {
            if let frame = current {
                Button("Delete This Frame…") { prepareDelete("Delete this frame?") { [frame] } }
            }
            Divider()
            Button("Delete Last 5 Minutes…") { prepareDelete("Delete the last 5 minutes?") { await recorder.frames(lastMinutes: 5) } }
            Button("Delete Last 15 Minutes…") { prepareDelete("Delete the last 15 minutes?") { await recorder.frames(lastMinutes: 15) } }
            Button("Delete Last Hour…") { prepareDelete("Delete the last hour?") { await recorder.frames(lastMinutes: 60) } }
            Divider()
            Button("Delete This Day…") {
                prepareDelete("Delete \(day.formatted(.dateTime.weekday(.wide).month().day()))?") { (try? await recorder.db.frames(on: day)) ?? [] }
            }
        } label: {
            Image(systemName: "trash")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Delete screenshots from your history")
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            statusMessage = nil
        }
    }

    private func prepareDelete(_ title: String, _ load: @escaping () async -> [Frame]) {
        Task {
            let frames = await load()
            guard !frames.isEmpty else { flash("Nothing to delete"); return }
            deleteRequest = DeleteRequest(title: title, frames: frames)
        }
    }

    /// `-timelineQuery text` and `-timelineDay yyyy-MM-dd` on the command line, for screenshots and demos.
    private func applyLaunchOptions() {
        let defaults = UserDefaults.standard
        if let text = defaults.string(forKey: "timelineQuery") { query = text }
        if defaults.bool(forKey: "showRecap") { showRecap = true }
        if defaults.object(forKey: "previewZoom") != nil { zoom.set(scale: CGFloat(defaults.double(forKey: "previewZoom")), in: previewSize) }
        if let text = defaults.string(forKey: "timelineDay") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: text) { day = date }
        }
    }

    private func prepareExclusion(_ frame: Frame) {
        Task {
            let frames = (try? await recorder.db.frames(app: frame.app)) ?? []
            let bundleID = frame.bundle.isEmpty ? AppIcons.shared.bundleIdentifier(for: frame.app) : frame.bundle
            excludeRequest = ExcludeRequest(app: frame.app, bundleID: bundleID, frames: frames)
        }
    }

    private func performDelete(_ request: DeleteRequest) async {
        let removed = Set(request.frames.map(\.id))
        let anchor = current?.date
        await recorder.delete(request.frames)
        hits.removeAll { removed.contains($0.frame.id) }
        await reloadDays()
        loadedFrames = (try? await recorder.db.frames(on: day)) ?? []
        if loadedFrames.isEmpty, let other = days.first(where: { $0 != day && $0 <= day }) ?? days.first(where: { $0 != day }) {
            day = other
            return
        }
        if !displays.contains(display) { display = displays.first ?? 0 }
        if let filter = appFilter, !dayFrames.contains(where: { $0.app == filter }) { appFilter = nil }
        if let id = selectedID, removed.contains(id) {
            selectedID = nil
            let visible = frames
            if let anchor, let i = Activity.nearest(visible, to: anchor.timeIntervalSince1970) {
                select(visible[i].id, animated: false)
            } else if let last = visible.last {
                select(last.id, animated: false)
            }
        }
        flash("Deleted \(removed.count) \(removed.count == 1 ? "frame" : "frames")")
    }

    private var info: some View {
        HStack(spacing: 6) {
            if let frame = current {
                Text(frame.date.formatted(date: .abbreviated, time: .standard)).monospacedDigit()
                Text("·")
                Text(frame.app).bold()
                if !frame.title.isEmpty { Text("— \(frame.title)").lineLimit(1).foregroundStyle(.secondary) }
                Spacer()
                if let statusMessage { Text(statusMessage).foregroundStyle(.green) }
                Button(action: toggleStar) { Image(systemName: frame.starred ? "star.fill" : "star") }
                    .buttonStyle(.plain).foregroundStyle(frame.starred ? Color.yellow : .secondary)
                    .help("Star this screenshot to keep it forever (S)")
                Button { showText.toggle() } label: { Image(systemName: "text.alignleft") }
                    .buttonStyle(.plain).foregroundStyle(showText ? Color.accentColor : .secondary)
                    .help("Show the text recognized in this screenshot (T)")
                Button { prepareExclusion(frame) } label: { Image(systemName: "nosign") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Never record \(frame.app)")
                exportMenu
                deleteMenu
                if !frameText.isEmpty {
                    Button("Copy Text", action: copyText).buttonStyle(.plain).foregroundStyle(.tint)
                        .help("Copy the selected words, or all text if nothing is selected (⌘C)")
                }
                if let i = currentIndex { Text("\(i + 1) of \(frames.count)").foregroundStyle(.secondary) }
            }
        }
        .font(.callout)
        .frame(height: 28)
        .padding(.horizontal, 20)
    }

    private var filmstrip: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: cellSpacing) {
                        ForEach(frames) { frame in
                            FilmstripCell(frame: frame,
                                          url: recorder.framesRoot.appendingPathComponent(frame.path),
                                          selected: frame.id == selectedID)
                                .id(frame.id)
                                .onTapGesture { select(frame.id, animated: true) }
                        }
                    }
                    .background(ScrollViewFinder(bridge: bridge))
                    .padding(.horizontal, max(0, geometry.size.width / 2 - cellWidth / 2))
                }
                .onChange(of: scrollRequest) {
                    guard let request = scrollRequest else { return }
                    if request.animated {
                        withAnimation(.snappy) { proxy.scrollTo(request.id, anchor: .center) }
                    } else {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: cellHeight + 38)
        .background(.white.opacity(0.05))
        .overlay(alignment: .top) {
            Image(systemName: "arrowtriangle.down.fill").font(.caption2).foregroundStyle(.tint).offset(y: -1)
        }
        .onAppear {
            bridge.onScroll = { x in
                let visible = frames
                guard !visible.isEmpty else { return }
                let index = min(max(Int((x / (cellWidth + cellSpacing)).rounded()), 0), visible.count - 1)
                if visible[index].id != selectedID { selectedID = visible[index].id }
            }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            searchFilters
            resultRows
        }
        .frame(width: 320)
    }

    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Picker("When", selection: $searchRange) {
                    ForEach(SearchRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                Picker("App", selection: $searchApp) {
                    Text("Any app").tag(String?.none)
                    ForEach(allApps, id: \.app) { Text($0.app).tag(Optional($0.app)) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                Spacer()
            }
            Text(hits.count >= 200 ? "200+ results" : "\(hits.count) \(hits.count == 1 ? "result" : "results")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func moveResult(_ delta: Int) -> KeyPress.Result {
        guard !hits.isEmpty else { return .ignored }
        let current = hits.firstIndex { $0.frame.id == selectedID }
        let next = current.map { min(max($0 + delta, 0), hits.count - 1) } ?? (delta > 0 ? 0 : hits.count - 1)
        jump(to: hits[next].frame)
        return .handled
    }

    private var resultRows: some View {
        ScrollViewReader { proxy in
            resultList
                .onChange(of: selectedID) {
                    if let id = selectedID, hits.contains(where: { $0.id == id }) { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var resultList: some View {
        List(hits) { hit in
            Button { jump(to: hit.frame) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hit.frame.date.formatted(date: .abbreviated, time: .shortened)) · \(hit.frame.app)\(hit.frame.display > 0 ? " · " + Self.displayName(hit.frame.display) : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(hit.snippet.replacingOccurrences(of: "\n", with: " ")).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(hit.frame.id == selectedID ? Color.accentColor.opacity(0.25) : Color.clear)
        }
        .scrollContentBackground(.hidden)
        .overlay { if hits.isEmpty { Text("No matches").foregroundStyle(.secondary) } }
    }


    private func select(_ id: Int64, animated: Bool) {
        selectedID = id
        scrollRequest = ScrollRequest(id: id, animated: animated, nonce: (scrollRequest?.nonce ?? 0) + 1)
    }

    private func keepSelectionVisible() {
        let visible = frames
        guard !visible.isEmpty else { selectedID = nil; return }
        if let id = selectedID, visible.contains(where: { $0.id == id }) {
            select(id, animated: false)
        } else if let reference = dayFrames.first(where: { $0.id == selectedID }),
                  let i = Activity.nearest(visible, to: reference.date.timeIntervalSince1970) {
            select(visible[i].id, animated: false)
        } else if let last = visible.last {
            select(last.id, animated: false)
        }
    }

    private func jumpToAppSwitch(_ direction: Int) {
        let visible = frames
        guard let i = currentIndex else { return }
        select(visible[Activity.switchIndex(apps: visible.map(\.app), from: i, direction: direction)].id, animated: true)
    }

    private func jumpToEnd(first: Bool) {
        let visible = frames
        guard let target = first ? visible.first : visible.last else { return }
        select(target.id, animated: true)
    }

    private var frameText: String { fullText.isEmpty ? WordBox.text(of: boxes) : fullText }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $panelMode) {
                Text("Text").tag("text")
                Text("Summary").tag("summary")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if panelMode == "summary" {
                SummaryPanel(frame: current, db: recorder.db, summarizer: summarizer)
            } else {
                HStack {
                    Spacer()
                    if !frameText.isEmpty {
                        Button("Copy", action: copyText).buttonStyle(.plain).foregroundStyle(.tint)
                    }
                }
                if frameText.isEmpty {
                    Text(current == nil ? "" : "No text was recognized in this screenshot.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        Text(highlightedText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.04))
    }

    private var highlightedText: AttributedString {
        let text = frameText
        var attributed = AttributedString(text)
        for range in TextHighlight.ranges(in: text, terms: SearchQuery(query).highlightTerms) {
            if let target = Range(range, in: attributed) {
                attributed[target].backgroundColor = .yellow.opacity(0.35)
            }
        }
        return attributed
    }

    private func step(_ delta: Int) {
        guard let i = currentIndex else { return }
        select(frames[min(max(i + delta, 0), frames.count - 1)].id, animated: true)
    }

    private func jump(to frame: Frame) {
        let target = Calendar.current.startOfDay(for: frame.date)
        if target == day, loadedFrames.contains(where: { $0.id == frame.id }) {
            display = frame.display
            if let filter = appFilter, filter != frame.app { appFilter = nil }
            select(frame.id, animated: true)
        } else {
            pendingFrameID = frame.id
            pendingDisplay = frame.display
            day = target
        }
    }


    private func reloadDays() async {
        var loaded = (try? await recorder.db.days()) ?? []
        let today = Calendar.current.startOfDay(for: Date())
        let daysWithFrames = loaded
        if !loaded.contains(today) { loaded.insert(today, at: 0) }
        days = loaded
        if !didChooseInitialDay {
            didChooseInitialDay = true
            if day == today { day = Activity.initialDay(today: today, daysWithFrames: daysWithFrames) }
        }
        allApps = (try? await recorder.db.apps()) ?? []
        for pair in (try? await recorder.db.appBundles()) ?? [] { AppIcons.shared.learn(app: pair.app, bundle: pair.bundle) }
    }

    private func loadDay() async {
        loadedFrames = (try? await recorder.db.frames(on: day)) ?? []
        if let wanted = pendingDisplay { display = wanted }
        pendingDisplay = nil
        if !displays.contains(display) { display = displays.first ?? 0 }
        if let filter = appFilter, !dayFrames.contains(where: { $0.app == filter }) { appFilter = nil }
        if let id = pendingFrameID, frames.contains(where: { $0.id == id }) {
            select(id, animated: false)
        } else if let last = frames.last {
            select(last.id, animated: false)
        } else {
            selectedID = nil
        }
        pendingFrameID = nil
    }

    private func refreshFrames() async {
        let wasAtEnd = selectedID == nil || selectedID == frames.last?.id
        loadedFrames = (try? await recorder.db.frames(on: day)) ?? []
        if wasAtEnd, let last = frames.last { select(last.id, animated: false) }
    }

    private func runSearch() async {
        guard isSearching else { hits = []; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let bounds = searchRange.bounds(day: day)
        hits = (try? await recorder.db.search(query, app: searchApp, from: bounds.from, to: bounds.to)) ?? []
    }

    private func loadBoxes() async {
        guard let id = selectedID else { boxes = []; fullText = ""; return }
        let data = try? await recorder.db.boxes(for: id)
        let text = (try? await recorder.db.texts(for: [id]))?[id] ?? ""
        if !Task.isCancelled {
            fullText = text
            boxes = WordBox.recased(WordBox.unpack(data), from: text)
            boxesID = id
        }
    }

    private func loadImage() async {
        guard let frame = current else { image = nil; return }
        try? await Task.sleep(nanoseconds: 40_000_000)
        guard !Task.isCancelled else { return }
        let url = recorder.framesRoot.appendingPathComponent(frame.path)
        let loaded = await Task.detached { NSImage(contentsOf: url) }.value
        if !Task.isCancelled { image = loaded }
    }
}

private struct FilmstripCell: View {
    let frame: Frame
    let url: URL
    let selected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.white.opacity(0.08)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                }
            }
            .frame(width: cellWidth, height: cellHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: selected ? 3 : 0))
            .overlay(alignment: .topTrailing) {
                if frame.starred { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).padding(5) }
            }
            .overlay(alignment: .bottomLeading) {
                if let icon = AppIcons.shared.icon(for: frame.app) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18).padding(4)
                }
            }
            .scaleEffect(selected ? 1.04 : 1)
            Text(frame.date.formatted(date: .omitted, time: .standard))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .frame(width: cellWidth)
        .padding(.top, 10)
        .task { thumbnail = await Thumbnails.image(at: url) }
    }
}

enum Thumbnails {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL, maxPixel: Int = 400) async -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = downscaled(url, maxPixel: maxPixel) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    static func clear() { cache.removeAllObjects() }

    static func downscaled(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longest = max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        if longest > 0, longest <= maxPixel { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

@MainActor
final class ScrubBridge {
    weak var scrollView: NSScrollView? {
        didSet { if scrollView !== oldValue { observe() } }
    }
    var onScroll: ((CGFloat) -> Void)?
    private var token: NSObjectProtocol?

    private func observe() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        guard let clip = scrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScroll?(clip.bounds.origin.x) }
        }
    }
}

enum TextHighlight {
    static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
                found.append(range)
                searchStart = range.upperBound
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}

private struct DeleteRequest: Identifiable {
    let id = UUID()
    let title: String
    let frames: [Frame]
}

private struct ExcludeRequest: Identifiable {
    let id = UUID()
    let app: String
    let bundleID: String?
    let frames: [Frame]
}

private struct SearchKey: Hashable {
    let query: String
    let app: String?
    let range: SearchRange
    let day: Date
}

/// Not observable on purpose: it changes with every mouse move and nothing needs to redraw for it.
final class PointerTracker {
    var location: CGPoint?
}

private struct PinchStart {
    let zoom: PreviewZoom
    let anchor: CGPoint
}

private struct ScrollRequest: Equatable {
    let id: Int64
    let animated: Bool
    let nonce: Int
}

private struct ScrollViewFinder: NSViewRepresentable {
    let bridge: ScrubBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { bridge.scrollView = view.enclosingScrollView }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { bridge.scrollView = view.enclosingScrollView }
    }
}
