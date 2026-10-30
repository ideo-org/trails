//
//  SpatialMapView.swift
//  Trails
//
//  Google Maps view showing where scans were taken.
//

import SwiftUI
import SwiftData
import CoreLocation

// Fallback to MapKit if GoogleMaps isn't compiled in the target
#if canImport(GoogleMaps)
import GoogleMaps

struct SpatialMapView: View {
    @Query private var scans: [Scan]
    
    var body: some View {
        GoogleMapViewWrapper(scans: scans)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottom) {
                if scans.isEmpty {
                    Text("No Trails locations yet")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                }
            }
    }
}

struct GoogleMapViewWrapper: UIViewRepresentable {
    var scans: [Scan]
    
    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        // Default camera to US, but will fit bounds to scans if they exist
        options.camera = GMSCameraPosition.camera(withLatitude: 37.7749, longitude: -122.4194, zoom: 2.0)
        
        let mapView = GMSMapView(options: options)
        
        // Match Obsidian UI theme for map
        let darkStyle = """
        [
          { "elementType": "geometry", "stylers": [{"color": "#212121"}] },
          { "elementType": "labels.icon", "stylers": [{"visibility": "off"}] },
          { "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}] },
          { "elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}] },
          { "featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}] }
        ]
        """
        do {
            mapView.mapStyle = try GMSMapStyle(jsonString: darkStyle)
        } catch {
            print("Failed to load dark map style")
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        uiView.clear()
        
        var bounds = GMSCoordinateBounds()
        var hasValidCoords = false
        
        for scan in scans {
            guard let lat = scan.latitude, let lon = scan.longitude else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            
            let marker = GMSMarker(position: coord)
            marker.title = scan.title
            marker.snippet = "\(scan.pointCount) pts"
            // Use Trails scanner blue for the marker.
            marker.icon = GMSMarker.markerImage(with: UIColor(red: 47/255, green: 123/255, blue: 255/255, alpha: 1.0))
            marker.map = uiView
            
            bounds = bounds.includingCoordinate(coord)
            hasValidCoords = true
        }
        
        if hasValidCoords {
            let update = GMSCameraUpdate.fit(bounds, withPadding: 50.0)
            uiView.animate(with: update)
        }
    }
}

#else
import MapKit

// Fallback MapKit implementation for local testing without GMS package
struct SpatialMapView: View {
    @Query private var scans: [Scan]
    @State private var position: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $position) {
            ForEach(scans.filter { $0.latitude != nil && $0.longitude != nil }) { scan in
                Annotation(scan.title, coordinate: CLLocationCoordinate2D(latitude: scan.latitude!, longitude: scan.longitude!)) {
                    NavigationLink(destination: ScanDetailView(scan: scan)) {
                        VStack {
                            Image(systemName: "cube.fill")
                                .padding(8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted))
        .safeAreaInset(edge: .bottom) {
            if scans.isEmpty {
                VStack {
                    Text("No Trails locations yet")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                .padding()
            }
        }
    }
}
#endif
