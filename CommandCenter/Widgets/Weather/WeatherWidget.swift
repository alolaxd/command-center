import MapKit
import SwiftUI

struct WeatherWidget: DashboardWidget {
    static let kind = "weather"
    static let title = "Weather"
    static let symbol = "cloud.sun"
    static let summary = "Current conditions, 7-day forecast, radar mini-map and severe weather alerts (Open-Meteo)."
    static let category = WidgetCategory.information
    static let defaultSize = GridSize(3, 4)
    static let refreshInterval: TimeInterval? = 900

    let context: WidgetContext<WeatherConfiguration>
    @State private var vm = WeatherViewModel()

    init(context: WidgetContext<WeatherConfiguration>) { self.context = context }

    private var unit: String { context.config.fahrenheit ? "°F" : "°C" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = vm.report {
                let (desc, sym) = WeatherStore.describe(r.code, day: r.isDay)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: sym).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(r.temp.rounded()))\(unit)").font(.largeTitle.monospacedDigit().weight(.semibold))
                        Text("\(desc) · feels \(Int(r.feels.rounded()))°").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.config.place.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Label("\(r.humidity)%", systemImage: "humidity").font(.caption2).foregroundStyle(.secondary)
                        Label("\(Int(r.wind)) \(context.config.fahrenheit ? "mph" : "km/h")", systemImage: "wind").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if WeatherStore.isSevere(r.code) || (r.days.first.map { WeatherStore.isSevere($0.code) } ?? false) {
                    Label("Severe weather expected today", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                VStack(spacing: 3) {
                    ForEach(r.days) { d in
                        let (_, dsym) = WeatherStore.describe(d.code)
                        HStack {
                            Text(dayName(d.date)).font(.caption).frame(width: 36, alignment: .leading)
                            Image(systemName: dsym).symbolRenderingMode(.multicolor).frame(width: 22)
                            Text(d.precip > 0 ? "\(d.precip)%" : "").font(.caption2).foregroundStyle(.blue).frame(width: 30)
                            Text("\(Int(d.lo.rounded()))°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            tempBar(d, all: r.days)
                            Text("\(Int(d.hi.rounded()))°").font(.caption.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if context.config.showRadar, let t = vm.radarTemplate, context.size.h >= 4 {
                    RadarMapView(center: CLLocationCoordinate2D(latitude: context.config.place.lat, longitude: context.config.place.lon), template: t)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 80)
                        .accessibilityLabel("Precipitation radar")
                }
            } else if let e = vm.error {
                EmptyStateView(symbol: "exclamationmark.icloud", title: "Weather unavailable", message: e)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.refresh(context.config) }
        .onChange(of: context.config) { Task { await vm.refresh(context.config) } }
    }

    private func dayName(_ key: String) -> String {
        guard let d = Date.fromDayKey(key) else { return key }
        return Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.abbreviated))
    }

    private func tempBar(_ d: WeatherReport.Day, all: [WeatherReport.Day]) -> some View {
        let lo = all.map(\.lo).min() ?? 0, hi = all.map(\.hi).max() ?? 1
        let span = max(1, hi - lo)
        return GeometryReader { g in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.orange.opacity(0.75))
                        .frame(width: g.size.width * (d.hi - d.lo) / span)
                        .offset(x: g.size.width * (d.lo - lo) / span)
                }
        }
        .frame(height: 4)
    }
}

/// MapKit view with a RainViewer radar tile overlay.
struct RadarMapView: NSViewRepresentable {
    let center: CLLocationCoordinate2D
    let template: String

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = false
        map.isScrollEnabled = true
        map.showsCompass = false
        map.mapType = .mutedStandard
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)), animated: false)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        if context.coordinator.template != template {
            map.removeOverlays(map.overlays)
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = false
            overlay.maximumZ = 7
            map.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.template = template
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var template: String?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKTileOverlayRenderer(overlay: overlay as! MKTileOverlay)
            r.alpha = 0.7
            return r
        }
    }
}
