import SwiftUI
import MapKit
import CoreLocation

// MARK: - 行程列表

struct TripsView: View {
    @ObservedObject var api: TeslaAPI

    var body: some View {
        NavigationView {
            ZStack {
                L.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        summaryCard
                        if api.trips.isEmpty {
                            emptyCard
                        } else {
                            ForEach(api.trips) { t in
                                NavigationLink(destination: TripDetailView(trip: t, api: api)) {
                                    TripRow(trip: t)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .refreshable { await api.loadTrips() }
            .task {
                if api.trips.isEmpty { await api.loadTrips() }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var summaryCard: some View {
        LCard {
            HStack(spacing: 0) {
                stat("\(api.trips.count)", "行程")
                divider
                stat(String(format: "%.0f", api.trips.reduce(0) { $0 + $1.distanceKm }), "总里程 km")
                divider
                stat(totalDurationText, "总时长", small: true)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(L.line).frame(width: 1, height: 34)
    }

    private func stat(_ v: String, _ l: String, small: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .font(.system(size: small ? 17 : 20, weight: .bold))
                .foregroundColor(L.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l).font(.system(size: 10)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalDurationText: String {
        let m = api.trips.reduce(0) { $0 + $1.durationMin }
        if m <= 0 { return "0 分" }
        return m >= 60 ? "\(m / 60)时\(m % 60)分" : "\(m)分"
    }

    private var emptyCard: some View {
        LCard {
            VStack(spacing: 8) {
                Image(systemName: "car.side").font(.system(size: 26)).foregroundColor(L.sub)
                Text("还没有行程记录").font(.system(size: 13)).foregroundColor(L.text)
                Text("开一段路后自动生成").font(.system(size: 11)).foregroundColor(L.sub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }
}

// MARK: - 单行

struct TripRow: View {
    let trip: Trip

    var body: some View {
        LCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateText).font(.system(size: 12, weight: .medium)).foregroundColor(L.text)
                    Text(timeText).font(.system(size: 10)).foregroundColor(L.sub)
                }
                .frame(width: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", trip.distanceKm))
                        .font(.system(size: 22, weight: .bold)).foregroundColor(L.text)
                    Text("公里").font(.system(size: 9)).foregroundColor(L.sub)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(duText).font(.system(size: 12, weight: .medium)).foregroundColor(L.text)
                    HStack(spacing: 4) {
                        if let b0 = trip.startBattery, let b1 = trip.endBattery {
                            Text("\(b0)%→\(b1)%").font(.system(size: 10)).foregroundColor(L.sub)
                        }
                        if let s = trip.maxSpeedKmh, s > 0 {
                            Text("· 最高\(s)").font(.system(size: 10)).foregroundColor(L.sub)
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(L.sub)
            }
        }
    }

    private var dateObj: Date { Date(timeIntervalSince1970: TimeInterval(trip.startTs)) }
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "MM-dd"; return f.string(from: dateObj)
    }
    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: dateObj)
    }
    private var duText: String {
        let m = trip.durationMin
        return m >= 60 ? "\(m / 60)时\(m % 60)分" : "\(m) 分钟"
    }
}

// MARK: - 行程详情（地图轨迹）

struct TripDetailView: View {
    let trip: Trip
    @ObservedObject var api: TeslaAPI
    @State private var track: [TrackPoint] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            L.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    RouteMap(points: track)
                        .ignoresSafeArea(edges: .top)
                    if loading {
                        ProgressView().scaleEffect(1.2)
                    } else if track.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "map").font(.system(size: 28)).foregroundColor(L.sub)
                            Text("这段行程没有轨迹点").font(.system(size: 12)).foregroundColor(L.sub)
                        }
                    }
                }
                .frame(height: 320)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        detailCard
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            track = await api.loadTripTrack(id: trip.id)
            loading = false
        }
    }

    private var titleText: String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(trip.startTs)))
    }

    private var detailCard: some View {
        LCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    tile(String(format: "%.1f", trip.distanceKm), "公里", L.orange)
                    tile("\(trip.durationMin)", "分钟", L.blue)
                }
                HStack(spacing: 8) {
                    tile("\(trip.avgSpeedKmh ?? 0)", "平均 km/h", L.green)
                    tile("\(trip.maxSpeedKmh ?? 0)", "最高 km/h", L.purple)
                }
                HStack(spacing: 8) {
                    tile("\(trip.startBattery ?? 0)%", "出发电量", L.text)
                    tile("\(trip.endBattery ?? 0)%", "到达电量", L.text)
                }
            }
        }
    }

    private func tile(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 18, weight: .semibold)).foregroundColor(c)
            Text(l).font(.system(size: 9)).foregroundColor(L.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(L.fill))
    }
}

// MARK: - 地图（画轨迹）

struct RouteMap: UIViewRepresentable {
    let points: [TrackPoint]

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.isZoomEnabled = true
        m.pointOfInterestFilter = .excludingAll
        return m
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        guard points.count > 1 else { return }

        // 特斯拉返回的是 WGS-84，中国境内地图需要 GCJ-02
        // 车辆已给国内坐标系时不转换；老数据是 WGS-84，需要转成 GCJ-02
        let alreadyGCJ = points.contains { $0.frame == "gcj" }
        let coords: [(lat: Double, lon: Double)] = alreadyGCJ
            ? points.map { (lat: $0.lat, lon: $0.lon) }
            : points.map { CoordTransform.toGCJ(lat: $0.lat, lon: $0.lon) }
        var cl = coords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }

        map.addOverlay(MKPolyline(coordinates: &cl, count: cl.count))

        let start = MKPointAnnotation()
        start.coordinate = cl.first!
        start.title = "起点"
        let end = MKPointAnnotation()
        end.coordinate = cl.last!
        end.title = "终点"
        map.addAnnotations([start, end])

        var rect = MKMapRect.null
        for c in cl {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor(red: 1.0, green: 0.62, blue: 0.12, alpha: 1)
                r.lineWidth = 4
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "pin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.markerTintColor = annotation.title == "起点"
                ? UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
                : UIColor(red: 1.0, green: 0.62, blue: 0.12, alpha: 1)
            v.displayPriority = .required
            return v
        }
    }
}

// MARK: - WGS-84 → GCJ-02

enum CoordTransform {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    static func toGCJ(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        // 境外不做偏移
        if lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271 {
            return (lat, lon)
        }
        var dLat = transformLat(lon - 105.0, lat - 35.0)
        var dLon = transformLon(lon - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (lat + dLat, lon + dLon)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
