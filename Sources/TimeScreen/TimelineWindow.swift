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
    @State private var copiedMessage: String?
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
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map { $0.replacingOccurrences(of: "\"", with: "") }
        return WordBox.matches(boxes, terms: terms)
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
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(characters: ["c"], phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            copyText()
            return .handled
        }
        .onChange(of: selectedID) { selection = nil }
        .onAppear { focused = true }
        .task { await reloadDays() }
        .task(id: day) { await loadDay() }
        .task(id: SearchKey(query: query, app: searchApp, range: searchRange, day: day)) { await runSearch() }
        .onChange(of: appFilter) { keepSelectionVisible() }
        .task(id: selectedID) { await loadImage() }
        .task(id: BoxKey(id: selectedID, searching: isSearching)) { await loadBoxes() }
        .onChange(of: recorder.revision) {
            Task {
                await reloadDays()
                if Calendar.current.isDateInToday(day) { await refreshFrames() }
            }
        }
    }


    private var topBar: some View {
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

            Spacer()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search everything you've seen", text: $query)
                    .textFieldStyle(.plain)
                if isSearching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 420)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Close (esc)")
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
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .overlay { highlightOverlay }
                    .overlay { selectionOverlay }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.5), radius: 20)
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
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let a = value.startLocation, b = value.location
                let rect = CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                                  width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)
                selection = hypot(a.x - b.x, a.y - b.y) < 3 ? nil : rect
            })
        }
    }

    private func copyText() {
        let words = selection == nil ? boxes : selectedWords
        guard !words.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(WordBox.text(of: words), forType: .string)
        copiedMessage = selection == nil ? "Copied all text" : "Copied \(words.count) \(words.count == 1 ? "word" : "words")"
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedMessage = nil
        }
    }

    private var info: some View {
        HStack(spacing: 6) {
            if let frame = current {
                Text(frame.date.formatted(date: .abbreviated, time: .standard)).monospacedDigit()
                Text("·")
                Text(frame.app).bold()
                if !frame.title.isEmpty { Text("— \(frame.title)").lineLimit(1).foregroundStyle(.secondary) }
                Spacer()
                if let copiedMessage { Text(copiedMessage).foregroundStyle(.green) }
                if !boxes.isEmpty {
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
                guard !frames.isEmpty else { return }
                let index = min(max(Int((x / (cellWidth + cellSpacing)).rounded()), 0), frames.count - 1)
                if frames[index].id != selectedID { selectedID = frames[index].id }
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

    private var resultRows: some View {
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
        if !loaded.contains(today) { loaded.insert(today, at: 0) }
        days = loaded
        allApps = (try? await recorder.db.apps()) ?? []
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
        guard let id = selectedID else { boxes = []; return }
        let data = try? await recorder.db.boxes(for: id)
        if !Task.isCancelled { boxes = WordBox.unpack(data) }
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
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    static func image(at url: URL, maxPixel: Int = 400) async -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = downscaled(url, maxPixel: maxPixel) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

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
            self?.onScroll?(clip.bounds.origin.x)
        }
    }
}

private struct SearchKey: Hashable {
    let query: String
    let app: String?
    let range: SearchRange
    let day: Date
}

private struct BoxKey: Hashable {
    let id: Int64?
    let searching: Bool
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
