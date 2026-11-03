import SwiftUI
import MapKit

/// 首页「车在哪」卡片：小地图 + 导航按钮
struct LocationCard: View {
    let lat: Double?
    let lon: Double?
    var staleText: String? = nil
    var onNavigate: () -> Void

    private var coord: CLLocationCoordinate2D? {
        guard let lat, let lon, abs(lat) > 0.001, abs(lon) > 0.001 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let c = coord {
                ZStack(alignment: .bottomTrailing) {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                            center: c,
                            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))),
                        interactionModes: [],
                        annotationItems: [Pin(coord: c)]) { pin in
                        MapAnnotation(coordinate: pin.coord) {
                            ZStack {
                                Circle().fill(L.sand.opacity(0.25)).frame(width: 34, height: 34)
                                Circle().fill(L.sand).frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(L.line, lineWidth: 1)
                    )

                    Button {
                        Haptics.tap()
                        onNavigate()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill").font(.app(10))
                            Text("导航过去").font(.app(11, .medium))
                        }
                        .foregroundColor(L.bg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(L.sand))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
                if let t = staleText {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.app(9))
                        Text(t).font(.app(10))
                        Spacer()
                    }
                    .foregroundColor(L.dim)
                    .padding(.top, 6)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash").font(.app(13)).foregroundColor(L.dim)
                    Text("车辆没有上报位置").font(.app(12)).foregroundColor(L.sub)
                    Spacer()
                }
                .padding(16)
            }
        }
    }

    private struct Pin: Identifiable {
        let id = UUID()
        let coord: CLLocationCoordinate2D
    }
}
