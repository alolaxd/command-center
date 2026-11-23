import EventKit
import SwiftUI

struct CalendarWidget: DashboardWidget {
    static let kind = "calendar"
    static let title = "Calendar"
    static let symbol = "calendar"
    static let summary = "Day / 3-day / week view of Apple Calendar with click-to-create, drag-to-resize and conflict highlighting."
    static let category = WidgetCategory.productivity
    static let minSize = GridSize(3, 3)
    static let defaultSize = GridSize(5, 4)
    static let refreshInterval: TimeInterval? = 60

    let context: WidgetContext<CalendarConfiguration>
    @State private var vm = CalendarViewModel()
    @State private var draft: Date?
    @State private var draftTitle = ""
    private var ek: EventKitService { .shared }

    init(context: WidgetContext<CalendarConfiguration>) { self.context = context }

    private var config: CalendarConfiguration { context.config }
    private var hourH: CGFloat { CGFloat(config.hourHeight) }

    var body: some View {
        VStack(spacing: 4) {
            if !ek.eventsAuthorized {
                PermissionPrompt(symbol: "calendar", title: "Calendar access needed",
                                 message: "Allow access to show and edit your events.", buttonTitle: "Allow Access") {
                    Task { await ek.requestEvents(); vm.load(config) }
                }
            } else {
                header
                allDayRow
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            hourLabels
                            ForEach(vm.days(config), id: \.self) { day in dayColumn(day) }
                        }
                        .frame(height: hourH * 24)
                    }
                    .onAppear { proxy.scrollTo("hour-\(config.startHour)", anchor: .top) }
                }
            }
        }
        .refreshing(every: Self.refreshInterval) { vm.load(config) }
        .onChange(of: ek.changeToken) { vm.load(config) }
        .onChange(of: config) { vm.load(config) }
        .popover(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New event · \(draft?.formatted(date: .abbreviated, time: .shortened) ?? "")").font(.headline)
                TextField("Title", text: $draftTitle).onSubmit(createDraft).frame(width: 240)
                HStack { Spacer(); Button("Cancel") { draft = nil }; Button("Create", action: createDraft).keyboardShortcut(.defaultAction) }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { vm.shift(-1, config) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).accessibilityLabel("Previous")
            Button("Today") { vm.goToday(config) }.controlSize(.small)
            Button { vm.shift(1, config) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).accessibilityLabel("Next")
            Text(vm.anchor.formatted(.dateTime.month(.wide).year())).font(.callout.weight(.semibold))
            Spacer()
            Picker("", selection: Binding(get: { config.mode }, set: { var c = config; c.mode = $0; context.updateConfig(c) })) {
                ForEach(CalendarConfiguration.Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("").frame(width: 34)
            ForEach(vm.days(config), id: \.self) { day in
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.caption.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.accentColor : .secondary)
                    ForEach(vm.allDay(on: day), id: \.eventIdentifier) { e in
                        Text(e.title ?? "").font(.caption2).lineLimit(1).padding(.horizontal, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(cgColor: e.calendar.cgColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!.formatted(.dateTime.hour()))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 34, height: hourH, alignment: .topTrailing)
                    .offset(y: -5)
                    .id("hour-\(h)")
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle().fill(.clear).frame(height: hourH)
                            .overlay(alignment: .top) { Divider().opacity(0.5) }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    let minutes = Int(tap.location.y / hourH * 60) / 15 * 15
                    draft = Calendar.current.date(byAdding: .minute, value: minutes, to: day)
                    draftTitle = ""
                })

                let dayEvents = vm.events(on: day)
                ForEach(Array(layoutColumns(dayEvents).enumerated()), id: \.offset) { _, item in
                    eventBlock(item.event, column: item.column, columns: item.count, width: geo.size.width)
                }

                if Calendar.current.isDate(vm.now, inSameDayAs: day) {
                    let y = CGFloat(vm.now.timeIntervalSince(day) / 3600) * hourH
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Rectangle().fill(.red).frame(height: 1)
                    }
                    .offset(x: -3, y: y - 3)
                    .accessibilityLabel("Current time")
                }
            }
        }
        .overlay(alignment: .leading) { Divider().opacity(0.5) }
    }

    /// Side-by-side columns for overlapping events.
    private func layoutColumns(_ events: [EKEvent]) -> [(event: EKEvent, column: Int, count: Int)] {
        var result: [(EKEvent, Int)] = []
        var columnsEnd: [Date] = []
        for e in events {
            if let col = columnsEnd.firstIndex(where: { $0 <= e.startDate }) { columnsEnd[col] = e.endDate; result.append((e, col)) }
            else { columnsEnd.append(e.endDate); result.append((e, columnsEnd.count - 1)) }
        }
        return result.map { item in
            let overlapping = result.filter { $0.0.startDate < item.0.endDate && item.0.startDate < $0.0.endDate }
            return (item.0, item.1, (overlapping.map(\.1).max() ?? 0) + 1)
        }
    }

    private func eventBlock(_ e: EKEvent, column: Int, columns: Int, width: CGFloat) -> some View {
        let day = Calendar.current.startOfDay(for: e.startDate)
        let end = (vm.resizing?.id == e.eventIdentifier ? vm.resizing?.end : nil) ?? e.endDate!
        let y = CGFloat(e.startDate.timeIntervalSince(day) / 3600) * hourH
        let h = max(14, CGFloat(end.timeIntervalSince(e.startDate) / 3600) * hourH)
        let colW = (width - 2) / CGFloat(columns)
        let conflict = vm.conflicts.contains(e.eventIdentifier ?? "")
        let color = Color(cgColor: e.calendar.cgColor)
        return VStack(alignment: .leading, spacing: 0) {
            Text(e.title ?? "").font(.caption2.weight(.semibold)).lineLimit(h > 28 ? 2 : 1)
            if h > 30 {
                Text("\(e.startDate.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if h > 44, let loc = e.location, !loc.isEmpty {
                Label(loc, systemImage: "mappin").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .frame(width: colW - 2, height: h, alignment: .topLeading)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(conflict ? Color.red : color.opacity(0.6), lineWidth: conflict ? 1.5 : 0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.clear).frame(height: 6).contentShape(Rectangle())
                .onHover { $0 ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        let minutes = (Double(g.translation.height / hourH) * 60 / 15).rounded() * 15
                        vm.resizing = (e.eventIdentifier ?? "", e.endDate.addingTimeInterval(minutes * 60))
                    }
                    .onEnded { _ in vm.commitResize(e, config: config) })
        }
        .offset(x: 1 + CGFloat(column) * colW, y: y)
        .help(conflict ? "Conflicts with another event" : (e.title ?? ""))
        .contextMenu {
            Button("Open in Calendar") { NSWorkspace.shared.open(URL(string: "ical://")!) }
            Button("Delete Event", role: .destructive) { CalendarStore.delete(e); vm.load(config) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.title ?? ""), \(e.startDate.formatted(date: .omitted, time: .shortened))\(conflict ? ", conflict" : "")")
    }

    private func createDraft() {
        guard let start = draft else { return }
        CalendarStore.create(title: draftTitle.isEmpty ? "New Event" : draftTitle, start: start, end: start.addingTimeInterval(3600),
                             calendarID: config.calendarIDs.first)
        draft = nil
        vm.load(config)
    }
}
